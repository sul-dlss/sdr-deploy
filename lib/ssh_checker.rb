# frozen_string_literal: true

# Service class for checking SSH connections
class SshChecker
  def self.check(environment:, repos:)
    new(environment:, repos:).check_ssh
  end

  attr_reader :environment, :repos

  def initialize(environment:, repos:)
    @environment = environment
    @repos = repos
  end

  def check_ssh
    puts "repos to SSH check: #{repos.map(&:name).join(', ')}"
    results = Parallel.map(repos, in_processes: Settings.num_parallel_processes) { |repo| check_repo(repo) }.flatten

    failed_results = results.reject { |result| result[:status] }
    report_failures(failed_results)
    raise Thor::Error, 'One or more SSH checks failed' if failed_results.any?
  end

  private

  def check_repo(repo)
    strategy = DeploymentStrategy.for(repo:)
    within_project_dir(repo:, environment:) do |environment|
      puts "checking SSH for #{repo.name} (#{environment}, #{repo.deployment_strategy || 'capistrano'})"
      status, output = strategy.check_ssh(environment:)
      { repo: repo.name, environment:, status:, output: }
    end
  end

  def report_failures(failed_results)
    failed_results.each do |result|
      warn "SSH check failed for #{result[:repo]} (#{result[:environment]}):\n#{result[:output]}"
    end
  end
end
