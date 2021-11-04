# frozen_string_literal: true

# Service class for checking SSH connections
class SshChecker
  def self.check(environment:)
    new(environment: environment).check_ssh
  end

  attr_reader :environment

  def initialize(environment:)
    @environment = environment
  end

  def check_ssh
    puts "repos to SSH check: #{repos.map(&:name).join(', ')}"
    repos.each do |repo|
      repo_updater = RepoUpdater.new(repo: repo.name)

      within_project_dir(repo_updater.repo_dir) do
        puts "Installing gems for #{repo_updater.repo_dir}"
        ErrorEmittingExecutor.execute('bundle install')
        puts "running 'cap #{environment} ssh_check' for #{repo_updater.repo_dir}"
        ErrorEmittingExecutor.execute("bundle exec cap #{environment} ssh_check")
      end
    end
  end

  private

  def repos
    @repos ||= Settings.repositories
  end
end
