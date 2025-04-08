# frozen_string_literal: true

# Service class for tagging repositories
class Tagger
  def self.create(tag_name:, tag_message:, repos:)
    new(tag_name:, repos:).create(tag_message:)
  end

  def self.delete(tag_name:, repos:)
    new(tag_name:, repos:).delete
  end

  def self.verify(tag_name:, repos:)
    new(tag_name:, repos:).verify
  end

  attr_reader :tag_name, :repos

  def initialize(tag_name:, repos:)
    @tag_name = tag_name
    @repos = repos
  end

  def create(tag_message:)
    render_markdown('***')
    render_markdown("# Creating tag '#{tag_name}'")
    render_markdown(repos.map { |repo| "* #{repo.name}" }.join("\n"))
    Parallel.each(repos, in_processes: Settings.num_parallel_processes) do |repo|
      within_project_dir(repo:) do
        ErrorEmittingExecutor.execute("git tag -a #{tag_name} -m '#{tag_message}'", exit_on_error: true)
        ErrorEmittingExecutor.execute("git push origin #{tag_name}", exit_on_error: true)
      end
    end
  end

  def verify
    render_markdown('***')
    render_markdown("# Verifying tag '#{tag_name}'")
    render_markdown(repos.map { |repo| "* #{repo.name}" }.join("\n"))
    Parallel.each(repos, in_processes: Settings.num_parallel_processes) do |repo|
      within_project_dir(repo:) do
        ErrorEmittingExecutor.execute('git fetch --tags')
        out, err, status = Open3.capture3("git tag -l #{tag_name}")
        unless status.success?
          puts colorize_failure("error checking for tag '#{tag_name}' in #{repo.name}: #{err}")
          next
        end
        if out.include?(tag_name)
          puts colorize_success("tag '#{tag_name}' found in #{repo.name}")
        else
          puts colorize_failure("tag '#{tag_name}' not found in #{repo.name}")
        end
      end
    end
  end

  def delete
    render_markdown('***')
    render_markdown("# Deleting tag '#{tag_name}'")
    render_markdown(repos.map { |repo| "* #{repo.name}" }.join("\n"))
    Parallel.each(repos, in_processes: Settings.num_parallel_processes) do |repo|
      within_project_dir(repo:) do
        ErrorEmittingExecutor.execute("git tag -d #{tag_name}", exit_on_error: true)
        ErrorEmittingExecutor.execute("git push --delete origin #{tag_name}", exit_on_error: true)
      end
    end
  end
end
