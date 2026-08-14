# frozen_string_literal: true

# Base class and factory for repository-specific deployment behavior.
class DeploymentStrategy
  class CommandFailed < StandardError; end

  def self.for(repo:, target: nil)
    strategy = repo.deployment_strategy || 'capistrano'

    case strategy.to_s
    when 'capistrano'
      DeploymentStrategies::Capistrano.new(repo:, target:)
    when 'kamal'
      DeploymentStrategies::Kamal.new(repo:, target:)
    else
      raise ArgumentError, "Unknown deployment strategy '#{strategy}' for #{repo.name}"
    end
  end

  attr_reader :repo, :repo_dir, :target

  def initialize(repo:, target:)
    @repo = repo
    @repo_dir = File.expand_path(RepoUpdater.new(repo:).repo_dir)
    @target = target
  end

  # override in subclasses to perform preflight checks before deployment
  def self.preflight!; end

  private

  def capture_command(*command, command_env: {})
    output = []
    status = nil

    Open3.popen2e(command_env, *command) do |stdin, combined_output, wait_thread|
      stdin.close
      combined_output.each_line { |line| output << line }
      status = wait_thread.value
    end

    [status.success?, output.join]
  end

  def run_command(*command)
    status, output = capture_command(*command)
    return output if status

    raise CommandFailed, "Command failed: #{command.join(' ')}\n#{output}"
  end
end
