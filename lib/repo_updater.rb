# frozen_string_literal: true

require 'fileutils'

# Update locally cached git repositories, remove extraneous ones
class RepoUpdater
  def self.update(repos:, prune: false)
    @progress_bar = progress_bar(repos)
    @progress_bar.start
    Parallel.each(
      repos,
      in_processes: Settings.num_parallel_processes,
      finish: ->(repo, _i, _result) do
        File.open(Settings.progress_file, 'a') { |f| f.write("#{Time.now} : #{repo.name} repo update complete\n") }
        @progress_bar.advance(repo: repo.name)
      end
    ) { |repo| new(repo:).update_or_create_repo }
    prune_removed_repos_from_cache!(repos) if prune
  end

  def self.progress_bar(repos)
    TTY::ProgressBar.new(
      'Updating cached git repository [:bar] (:current/:total, ETA: :eta) :repo',
      bar_format: :box,
      total: repos.count
    )
  end
  private_class_method :progress_bar

  def self.prune_removed_repos_from_cache!(repos)
    Dir["#{Settings.work_dir}/*/*"].each do |cached_dir|
      next if repos.map(&:name).any? { |repo_name| cached_dir.end_with?(repo_name) }

      FileUtils.rm_rf(cached_dir)
    end
  end
  private_class_method :prune_removed_repos_from_cache!

  attr_reader :repo, :repo_dir

  def initialize(repo:)
    @repo = repo
    @repo_dir = File.join(Settings.work_dir, repo.name)
  end

  def already_created?
    File.exist?(repo_dir)
  end

  def update_or_create_repo
    if already_created?
      update_repo
    else
      create_repo
    end
  end

  def delete_repo
    FileUtils.rm_rf(repo_dir)
  end

  def update_repo
    within_project_dir(repo:) do
      ErrorEmittingExecutor.execute('git fetch --tags origin', exit_on_error: true)
      ErrorEmittingExecutor.execute('git reset --hard $(git symbolic-ref refs/remotes/origin/HEAD)',
                                    exit_on_error: true)
      ErrorEmittingExecutor.execute('bundle install')
    end
  end

  def create_repo
    FileUtils.mkdir_p(repo_dir)
    within_project_dir(repo:) do
      ErrorEmittingExecutor.execute("git clone --tags git@github.com:#{repo.name}.git .", exit_on_error: true)
      ErrorEmittingExecutor.execute('git fetch --tags origin', exit_on_error: true)
      ErrorEmittingExecutor.execute('bundle install')
    end
  end
end
