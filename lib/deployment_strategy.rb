# frozen_string_literal: true

require 'tmpdir'

# Base class and factory for repository-specific deployment behavior.
class DeploymentStrategy
  class CommandFailed < StandardError; end

  def self.for(repo:, ref: nil, target: nil)
    strategy = repo.deployment_strategy || 'capistrano'

    case strategy.to_s
    when 'capistrano'
      CapistranoDeploymentStrategy.new(repo:, ref:, target:)
    when 'kamal'
      KamalDeploymentStrategy.new(repo:, ref:, target:)
    else
      raise ArgumentError, "Unknown deployment strategy '#{strategy}' for #{repo.name}"
    end
  end

  attr_reader :ref, :repo, :repo_dir, :target

  def initialize(repo:, ref:, target:)
    @repo = repo
    @repo_dir = File.expand_path(RepoUpdater.new(repo:).repo_dir)
    @ref = ref
    @target = target
  end

  def preflight!; end

  private

  def capture_command(environment, *command)
    output = []
    status = nil

    Open3.popen2e(environment, *command) do |stdin, combined_output, wait_thread|
      stdin.close
      combined_output.each_line { |line| output << line }
      status = wait_thread.value
    end

    [status.success?, output.join]
  end

  def run_command!(environment, *command)
    status, output = capture_command(environment, *command)
    return output if status

    raise CommandFailed, "Command failed: #{command.join(' ')}\n#{output}"
  end
end

# Executes the established Capistrano deployment workflow.
class CapistranoDeploymentStrategy < DeploymentStrategy
  def deploy(environment:, before_command: nil)
    status, output = run_before_command(environment, before_command)
    return [false, output] unless status

    deploy_status, deploy_output = deploy_command(environment)
    [deploy_status, output + deploy_output]
  rescue StandardError => e
    [false, "#{e.class}: #{e.message}\n"]
  end

  def check_ssh(environment:)
    capture_command({}, 'bundle', 'exec', 'cap', environment, 'ssh_check')
  end

  private

  def deploy_command(environment)
    set_deploy_target!
    capture_command(
      { 'SKIP_BUNDLE_AUDIT' => 'true' },
      'bundle', 'exec', 'cap', environment, 'deploy'
    )
  end

  def run_before_command(environment, before_command)
    return [true, ''] unless before_command

    capture_command(
      {},
      'bundle', 'exec', 'cap', environment, "remote_execute[#{before_command}]"
    )
  end

  def set_deploy_target!
    if target
      TTY::File.replace_in_file(
        'config/deploy.rb', /^ask :branch.+$/, "set :branch, '#{target}'", verbose: false
      )
    else
      TTY::File.replace_in_file('config/deploy.rb', /ask :branch/, 'set :branch', verbose: false)
    end
  end
end

# Executes Kamal from a clean, temporary clone at the selected commit.
class KamalDeploymentStrategy < DeploymentStrategy
  REQUIRED_EXECUTABLES = %w[bundle docker ssh ssh-add ssh-agent ssh-keygen vault].freeze

  def deploy(environment:, before_command: nil)
    with_source_clone { deploy_from_clone(environment, before_command) }
  rescue StandardError => e
    [false, "#{e.class}: #{e.message}\n"]
  end

  def check_ssh(environment:)
    capture_command({}, 'bin/kamal-otk', environment, 'server', 'exec', 'true')
  end

  def preflight!
    missing = REQUIRED_EXECUTABLES.reject { |executable| executable_available?(executable) }
    raise Thor::Error, "Missing commands required for Kamal: #{missing.join(', ')}" if missing.any?

    unless system('docker', 'buildx', 'version', out: File::NULL, err: File::NULL)
      raise Thor::Error, 'Kamal deployments require the Docker Buildx plugin'
    end

    return if system('vault', 'token', 'lookup', out: File::NULL, err: File::NULL)
    return if system('vault', 'login', '-method=oidc')

    raise Thor::Error, 'Unable to authenticate to Vault for the Kamal deployment'
  end

  private

  def deploy_from_clone(environment, before_command)
    status, output = run_before_command(environment, before_command)
    return [false, output] unless status

    deploy_status, deploy_output = capture_command({}, 'bin/kamal-otk', environment, 'deploy')
    [deploy_status, output + deploy_output]
  end

  def run_before_command(environment, before_command)
    return [true, ''] unless before_command

    capture_command({}, 'bin/kamal-otk', environment, 'server', 'exec', before_command)
  end

  def with_source_clone
    Dir.mktmpdir("#{File.basename(repo.name)}-deploy-") do |temporary_directory|
      clone_directory = File.join(temporary_directory, 'repo')
      clone_repository(clone_directory)
      run_command!({}, 'git', '-C', clone_directory, 'checkout', '--quiet', '--detach', ref)

      Dir.chdir(clone_directory) do
        ensure_bundle!
        return yield
      end
    end
  end

  def clone_repository(clone_directory)
    origin = run_command!({}, 'git', '-C', repo_dir, 'remote', 'get-url', 'origin').strip
    run_command!({}, 'git', 'clone', '--quiet', '--no-hardlinks', '--no-checkout', repo_dir, clone_directory)
    run_command!({}, 'git', '-C', clone_directory, 'remote', 'set-url', 'origin', origin)
  end

  def ensure_bundle!
    status, = capture_command({}, 'bundle', 'check')
    run_command!({}, 'bundle', 'install') unless status
  end

  def executable_available?(executable)
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |directory|
      File.executable?(File.join(directory, executable))
    end
  end
end
