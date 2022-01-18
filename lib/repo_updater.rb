# frozen_string_literal: true

require 'fileutils'

# Update locally cached git repositories, remove extraneous ones
class RepoUpdater
  def self.update(repos:)
    tmp_repos = Dir["#{Settings.work_dir}/*/*"].filter_map do |entry|
      entry.gsub("#{Settings.work_dir}/", '') if File.directory? entry
    end
    repo_names = repos.map(&:name)
    tmp_repos.each do |tmp_repo|
      unless repo_names.include? tmp_repo
        puts "Removing locally cached repo #{tmp_repo}"
        new(repo: tmp_repo).delete_repo
      end
    end

    @progress_bar = progress_bar(repos)
    @progress_bar.start
    repos.each do |repo|
      new(repo: repo.name).tap do |updater|
        @progress_bar.advance(repo: repo.name, operation: updater.operation_label)
        updater.update_or_create_repo
      end
    end
  end

  def self.progress_bar(repos)
    TTY::ProgressBar.new(
      ':operation cached git repository [:bar] (:current/:total, ETA: :eta) :repo',
      bar_format: :crate,
      total: repos.count
    )
  end
  private_class_method :progress_bar

  attr_reader :repo, :repo_dir

  def initialize(repo:)
    @repo = repo
    @repo_dir = File.join(Settings.work_dir, repo)
  end

  def already_created?
    File.exist?(repo_dir)
  end

  def operation_label
    return 'updating' if already_created?

    'creating'
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
    within_project_dir(repo_dir) do
      ErrorEmittingExecutor.execute('git fetch origin', exit_on_error: true)
      ErrorEmittingExecutor.execute('git reset --hard $(git symbolic-ref refs/remotes/origin/HEAD)',
                                    exit_on_error: true)
      ErrorEmittingExecutor.execute('bundle install')
    end
  end

  def create_repo
    FileUtils.mkdir_p(repo_dir)
    within_project_dir(repo_dir) do
      ErrorEmittingExecutor.execute("git clone --depth=5 git@github.com:#{repo}.git .", exit_on_error: true)
      ErrorEmittingExecutor.execute('bundle install')
    end
  end
end
