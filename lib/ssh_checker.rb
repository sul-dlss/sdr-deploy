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
    repos.each do |repo|
      within_project_dir(repo:, environment:) do |environment|
        puts "running 'cap #{environment} ssh_check' for #{repo.name}"
        ErrorEmittingExecutor.execute("bundle exec cap #{environment} ssh_check")
      end
    end
  end
end
