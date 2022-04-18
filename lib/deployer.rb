# frozen_string_literal: true

require 'English'
require 'launchy'

# Service class for deploying
class Deployer
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
    puts "repos to deploy: #{repos.map(&:name).join(', ')}"

    repos.each do |repo|
      puts "\n-------------------- BEGIN #{repo.name} --------------------\n"
      within_project_dir(repo: repo, environment: environment) do |env|
        puts "\n**** DEPLOYING #{repo.name} to #{env} ****\n"
        set_deploy_target!
        auditor.audit(repo: repo.name)
        cap_result = deploy(env) ? colorize_success('success') : colorize_failure('FAILED')
        puts "\n**** DEPLOYED #{repo.name} to #{env}; result: #{cap_result} ****\n"

        report_table << [
          env == environment ? repo.name : "#{repo.name} (#{env})",
          cap_result
        ]
      end
      puts "\n--------------------  END #{repo.name}  --------------------\n"
    end

    auditor.report

    puts "\n------- RESULTS: -------\n"
    puts report_table.render(:unicode)

    puts "Deployments to #{environment} complete. Opening #{status_url} in your browser so you can check statuses"
    Launchy.open(status_url)
  end

  private

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
    IO.popen({ 'SKIP_BUNDLE_AUDIT' => 'true' }, "bundle exec cap #{env} deploy") do |f|
      loop do
        puts f.readline
      rescue EOFError
        break
      end
    end
    $CHILD_STATUS.success?
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
