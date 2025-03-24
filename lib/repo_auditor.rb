# frozen_string_literal: true

# Service class for running bundle audit
class RepoAuditor
  def self.audit(repos:)
    new(repos:).audit_repos
  end

  attr_reader :repos, :auditor

  def initialize(repos:)
    @repos = repos
    @auditor = Auditor.new
  end

  def audit_repos
    puts "repos to bundle audit: #{repos.map(&:name).join(', ')}"
    Parallel.each(repos, in_processes: Settings.num_parallel_processes) do |repo|
      within_project_dir(repo:) do
        puts "running 'bundle audit' for #{repo.name}"
        auditor.audit(repo: repo.name) unless repo.skip_audit
      end
    end

    auditor.report
  end
end
