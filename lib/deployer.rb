# frozen_string_literal: true

require 'English'
require 'launchy'
require 'parallel'

# Service class for deploying
class Deployer
  Result = Struct.new(:repo, :env, :status, :output)

  def self.deploy(environment:, repos:, tag: nil)
    new(environment: environment, repos: repos, tag: tag).deploy_all
  end

  attr_reader :environment, :repos, :tag

  def initialize(environment:, repos:, tag: nil)
    @environment = environment
    @repos = repos
    @tag = tag
    ensure_tag_present_in_all_repos! if tag
    prompt_user_for_main_confirmation!
    prompt_user_for_approval_confirmation!
  end

  def deploy_all
    puts "Repositories: #{repos.map(&:name).join(', ')}"

    results = Parallel.map(repos, progress: 'Deploying...') do |repo|
      within_project_dir(repo: repo, environment: environment) do |env|
        auditor.audit(repo: repo.name)
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

    puts "Deployments to #{environment} complete. Opening #{status_url} in your browser so you can check statuses"
    Launchy.open(status_url)
  end

  private

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

  def prompt_user_for_main_confirmation!
    return if @tag && @tag != 'main'

    prompt_text = 'You are deploying without a tag, which will deploy the main branch of all repos.  Are you sure?'
    confirmation = TTY::Prompt.new.yes?(prompt_text) do |prompt|
      prompt.default(false)
    end

    abort 'Deployment to main aborted.' unless confirmation
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

  def ensure_tag_present_in_all_repos!
    return if repos_missing_tag.empty?

    raise "Aborting: git tag '#{tag}' is missing in these repos: #{repos_missing_tag.join(', ')}"
  end

  def repos_missing_tag
    @repos_missing_tag ||= repos.reject do |repo|
      Dir.chdir(RepoUpdater.new(repo: repo).repo_dir) { `git tag`.split.include?(tag) }
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
      text.sub!(/ask :branch/, 'set :branch')
    end

    File.write('config/deploy.rb', text)
  end

  def report_table
    @report_table ||= TTY::Table.new(header: %w[repo result])
  end
end
