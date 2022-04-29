# frozen_string_literal: true

# Service class for tagging repositories
class Tagger
  def self.create(tag_name:, tag_message:, repos:)
    new(tag_name: tag_name, repos: repos).create(tag_message: tag_message)
  end

  def self.delete(tag_name:, repos:)
    new(tag_name: tag_name, repos: repos).delete
  end

  attr_reader :tag_name, :repos

  def initialize(tag_name:, repos:)
    @tag_name = tag_name
    @repos = repos
  end

  def create(tag_message:)
    puts "creating tag in repos: #{repos.map(&:name).join(', ')}"
    Parallel.each(repos, in_processes: Settings.num_parallel_processes) do |repo|
      within_project_dir(repo: repo) do
        puts "creating tag '#{tag_name}' for #{repo.name}: #{tag_message}"
        ErrorEmittingExecutor.execute("git tag -a #{tag_name} -m '#{tag_message}'", exit_on_error: true)
        ErrorEmittingExecutor.execute("git push origin #{tag_name}", exit_on_error: true)
      end
    end
  end

  def delete
    puts "deleting tag in repos: #{repos.map(&:name).join(', ')}"
    Parallel.each(repos, in_processes: Settings.num_parallel_processes) do |repo|
      within_project_dir(repo: repo) do
        puts "deleting tag '#{tag_name}' from #{repo.name}"
        ErrorEmittingExecutor.execute("git tag -d #{tag_name}", exit_on_error: true)
        ErrorEmittingExecutor.execute("git push --delete origin #{tag_name}", exit_on_error: true)
      end
    end
  end
end
