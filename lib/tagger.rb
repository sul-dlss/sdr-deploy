# frozen_string_literal: true

# Service class for tagging repositories
class Tagger
  def self.tag(tag_name:, tag_message:)
    new(tag_name: tag_name, tag_message: tag_message).tag
  end

  attr_reader :tag_name, :tag_message

  def initialize(tag_name:, tag_message:)
    @tag_message = tag_message
    @tag_name = tag_name
  end

  def tag
    puts "repos to tag: #{repos.map(&:name).join(', ')}"
    repos.each do |repo|
      within_project_dir(RepoUpdater.new(repo: repo.name).repo_dir) do
        puts "creating tag '#{tag_name}' for #{repo.name}: #{tag_message}"
        ErrorEmittingExecutor.execute("git tag -a #{tag_name} -m '#{tag_message}'", exit_on_error: true)
      end
    end
  end

  private

  def repos
    @repos ||= Settings.repositories
  end
end
