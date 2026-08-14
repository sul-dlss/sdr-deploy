# frozen_string_literal: true

# Base class and factory for repository-specific deployment behavior.
class DeploymentStrategy
  class CommandFailed < StandardError; end

  def self.for(repo:, ref: nil, target: nil)
    strategy = repo.deployment_strategy || 'capistrano'

    case strategy.to_s
    when 'capistrano'
      DeploymentStrategies::Capistrano.new(repo:, ref:, target:)
    when 'kamal'
      DeploymentStrategies::Kamal.new(repo:, ref:, target:)
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

  def run_command(*command)
    status, output = capture_command({}, *command)
    return output if status

    raise CommandFailed, "Command failed: #{command.join(' ')}\n#{output}"
  end
end

require_relative 'deployment_strategies/capistrano'
require_relative 'deployment_strategies/kamal'
