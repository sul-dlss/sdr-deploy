# frozen_string_literal: true

require 'English'

# Service class for deploying
class Deployer # rubocop:disable Metrics/ClassLength
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
      'Deploying [:bar] (:current/:total, Elapsed: :elapsed, ETA: :eta)',
      bar_format: :box,
      total: @repos.count
    )
    @tag = tag
    ensure_tag_present_in_all_repos! if tag
  end

  def deploy_all # rubocop:disable Metrics/CyclomaticComplexity
    render_markdown('***')
    render_markdown("# Deploying the following repositories to #{environment} (#{tag || 'default branch'})")
    render_markdown(repos.map { |repo| "* #{repo.name}" }.join("\n"))

    prompt_user_for_branch_confirmation!
    prompt_user_for_approval_confirmation!

    progress_bar.start

    results = Parallel.map(
      repos,
      in_processes: Settings.num_parallel_processes,
      finish: lambda do |repo, _i, result_array|
        result_array.each do |result|
          progress_bar.log(log_result(result:))
        end
        progress_bar.advance
        next unless Settings.progress_file.enabled

        filename = File.join(Settings.progress_file.location, "#{File.basename(repo.name)}-deploy.log")
        File.write(filename, "#{Time.now} : #{repo.name} deploy complete")
      end
    ) do |repo|
      within_project_dir(repo:, environment:) do |env|
        # 2025-12-01 commented out after audit was removed from dlss-capistrano pending dev planning discussion
        # auditor.audit(repo: repo.name)
        run_before_command!(env)
        set_deploy_target!
        status, output = deploy(env)
        Result.new(repo.name, env, status, output)
      end
    end.flatten

    # 2025-12-01 commented out after audit was removed from dlss-capistrano pending dev planning discussion
    # auditor.report

    results
      .select { |result| result.output.match?('FAILED') }
      .each do |result|
        puts "Output from failed deployment of #{result.repo} (#{result.env}):\n#{result.output}"
    end

    render_markdown('***')
    render_markdown("**Deployments to #{environment} complete**")
    render_markdown("[Check service status](#{status_url})")
  end

  def ensure_tag_present_in_all_repos!
    return if repos_missing_tag.empty?

    raise "Aborting: git tag '#{tag}' is missing in these repos: #{repos_missing_tag.join(', ')}"
  end

  private

  def log_result(result:)
    stream = StringIO.new
    result_logger = logger(stream:)
    if result.status
      result_logger.success 'Deployed successfully', repo: result.repo, env: result.env
    else
      result_logger.error 'Deployment failed', repo: result.repo, env: result.env
    end
    stream.string
  end

  def logger(stream:)
    TTY::Logger.new do |config|
      config.handlers = [:console]
      config.output = stream
    end
  end

  def run_before_command!(env)
    return unless before_command

    `bundle exec cap #{env} remote_execute['#{before_command}'] 2>&1`
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
    if tag
      # Deploy the given tag
      TTY::File.replace_in_file('config/deploy.rb', /^ask :branch.+$/, "set :branch, '#{tag}'", verbose: false)
    else
      # Forces the `git:create_release` cap task to use the HEAD ref, which allows
      # different repositories to use different default branches.
      TTY::File.replace_in_file('config/deploy.rb', /ask :branch/, 'set :branch', verbose: false)
    end
  end
end
