# frozen_string_literal: true

# Resolves a deploy target to an immutable commit SHA in a cached repository.
class GitRefResolver
  class RefNotFound < StandardError; end

  def self.resolve(repo:, target: nil)
    new(repo:, target:).resolve
  end

  attr_reader :repo_dir, :target

  def initialize(repo:, target: nil)
    @repo_dir = File.expand_path(RepoUpdater.new(repo:).repo_dir)
    @target = target
  end

  def resolve
    candidates.each do |candidate|
      output, _error, status = Open3.capture3(
        'git', '-C', repo_dir, 'rev-parse', '--verify', '--end-of-options', candidate
      )
      return output.strip if status.success?
    end

    raise RefNotFound, "Git ref '#{target}' was not found in #{repo_dir}"
  end

  private

  def candidates
    return ['HEAD^{commit}'] unless target

    [
      "refs/tags/#{target}^{commit}",
      "refs/remotes/origin/#{target}^{commit}",
      "#{target}^{commit}"
    ]
  end
end
