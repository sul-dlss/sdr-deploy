# frozen_string_literal: true

require 'fileutils'

# Update locally cached git repositories
class RepoUpdater
  def self.update_all
    Settings.repositories.each { |repo| new(repo: repo.name).update_or_create_repo }
  end

  attr_reader :repo, :repo_dir

  def initialize(repo:)
    @repo = repo
    @repo_dir = File.join(Settings.work_dir, repo)
  end

  def update_or_create_repo
    puts "\n-------------------- updating #{repo}... --------------------\n"
    if File.exist?(repo_dir)
      update_repo
    else
      create_repo
    end
    puts "\n-------------------- ...updated #{repo}  --------------------\n"
  end

  def update_repo
    within_project_dir(repo_dir) do
      ErrorEmittingExecutor.execute('git fetch origin', exit_on_error: true)
      ErrorEmittingExecutor.execute('git reset --hard $(git symbolic-ref refs/remotes/origin/HEAD)',
                                    exit_on_error: true)
    end
  end

  def create_repo
    FileUtils.mkdir_p(repo_dir)
    puts "**** Creating #{repo}"
    within_project_dir(repo_dir) do
      ErrorEmittingExecutor.execute("git clone --depth=5 git@github.com:#{repo}.git .", exit_on_error: true)
    end
  end
end
