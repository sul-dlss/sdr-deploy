# frozen_string_literal: true

require 'English'

# Service class for deploying
# rubocop:disable Metrics/ClassLength
class Deployer
  Result = Struct.new(:repo, :env, :status, :output)

  def self.deploy(environment:, repos:, tag: nil, before_command: nil)
    new(environment:, repos:, tag:, before_command:).deploy_all
  end

  attr_reader :environment, :progress_bar, :repos, :tag, :before_command

  def initialize(environment:, repos:, tag: nil, before_command: nil)
    @before_command = before_command
    @environment = environment
    @repos = repos
    @progress_bar = TTY::ProgressBar.new(
      'Deploying [:bar] (:current/:total, ETA: :eta) :repo',
      bar_format: :box,
      total: @repos.count
    )
    @tag = tag
    ensure_tag_present_in_all_repos! if tag
    prompt_user_for_branch_confirmation!
    prompt_user_for_approval_confirmation!
  end

  # rubocop:disable Metrics/CyclomaticComplexity
  def deploy_all
    puts "Repositories: #{repos.map(&:name).join(', ')}"
    progress_bar.start

    results = Parallel.map(
      repos,
      in_processes: Settings.num_parallel_processes,
      finish: lambda do |repo, _i, _result|
        if Settings.progress_file.enabled
          filename = File.join(Settings.progress_file.location, "#{File.basename(repo.name)}-deploy.log")
          File.write(filename, "#{Time.now} : #{repo.name} deploy complete")
        end
        progress_bar.advance(repo: repo.name)
      end
    ) do |repo|
      within_project_dir(repo:, environment:) do |env|
        auditor.audit(repo: repo.name)
        run_before_command!(env)
        set_deploy_target!
        status, output = deploy(env)
        Result.new(
          env == environment ? repo.name : "#{repo.name} (#{env})",
          env,
          status ? colorize_success('success') : colorize_failure('FAILED'),
          output
        )
      end
    end.flatten

    auditor.report

    build_report_table!(results)

    puts report_table.render(:unicode)

    results
      .select { |result| result.status.match?('FAILED') }
      .each do |result|
      puts "Output from failed deployment of #{result.repo} (#{result.env}):\n#{result.output}"
    end

    puts "Deployments to #{environment} complete. Open #{status_url} to check service status."
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  def ensure_tag_present_in_all_repos!
    return if repos_missing_tag.empty?

    raise "Aborting: git tag '#{tag}' is missing in these repos: #{repos_missing_tag.join(', ')}"
  end

  private

  def run_before_command!(env)
    return unless before_command

    `bundle exec cap #{env} remote_execute['#{before_command}'] 2>&1`
  end

  def build_report_table!(results)
    results.each do |result|
      report_table << [
        result.repo,
        result.status
      ]
    end
  end

  def status_url
    Settings.supported_envs[environment]
  end

  def prompt_user_for_branch_confirmation!
    return if tag && tag != 'main'

    prompt_text = 'You are deploying without a tag, which will deploy the default branch of all repos.  Are you sure?'
    confirmation = TTY::Prompt.new.yes?(prompt_text) do |prompt|
      prompt.default(false)
    end

    abort 'Deployment to default branch aborted.' unless confirmation
  end

  def prompt_user_for_approval_confirmation!
    return if repos_requiring_confirmation.empty?

    prompt_text = "Some repos require approval before being deployed to #{environment} " \
                  "(#{repos_requiring_confirmation.join(', ')}). Has this been approved?"

    confirmation = TTY::Prompt.new.yes?(prompt_text) { |prompt| prompt.default(false) }

    abort 'Deployment not approved! Aborting.' unless confirmation
  end

  def repos_requiring_confirmation
    repos
      .select { |repo| Array(repo.confirmation_required_envs).include?(environment) }
      .map(&:name)
  end

  def repos_missing_tag
    @repos_missing_tag ||= repos.reject do |repo|
      Dir.chdir(RepoUpdater.new(repo:).repo_dir) { system("git show-ref -q #{tag}") }
    end.map(&:name)
  end

  def auditor
    @auditor ||= Auditor.new
  end

  def deploy(env)
    output = []

    IO.popen({ 'SKIP_BUNDLE_AUDIT' => 'true' }, "bundle exec cap #{env} deploy 2>&1") do |f|
      loop do
        output << f.readline
        # NOTE: Uncomment this if the deploy does something mysterious and you crave more observability.
        # puts output
      rescue EOFError
        break
      end
    end

    [$CHILD_STATUS.success?, output.join]
  end

  # Either deploy HEAD or the given tag
  def set_deploy_target!
    text = File.read('config/deploy.rb')

    if tag
      # Deploy the given tag
      text.sub!(/^ask :branch.+$/, "set :branch, '#{tag}'")
    else
      # Forces the `git:create_release` cap task to use the HEAD ref, which allows
      # different repositories to use different default branches.
      text.sub!('ask :branch', 'set :branch')
    end

    File.write('config/deploy.rb', text)
  end

  def report_table
    @report_table ||= TTY::Table.new(header: %w[repo result])
  end
end
# rubocop:enable Metrics/ClassLength
