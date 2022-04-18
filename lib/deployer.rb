# frozen_string_literal: true

require 'English'
require 'net/http'

# Service class for deploying
# rubocop:disable Metrics/ClassLength
class Deployer
  def self.deploy(environment:, repos:, tag: nil)
    new(environment: environment, repos: repos, tag: tag).deploy_all
  end

  attr_reader :environment, :repos, :tag

  def initialize(environment:, repos:, tag: nil)
    @environment = environment
    @repos = repos
    @tag = tag
    raise '*** ERROR: You must supply a tag to deploy (can set to main and confirm) ***' unless @tag

    ensure_tag_present_in_all_repos!
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

        status_check_result = case status_check(repo.status&.public_send(env))
                              when nil
                                colorize_success('N/A')
                              when true
                                colorize_success('success')
                              else
                                colorize_failure('FAILED')
                              end
        status_table << [
          env == environment ? repo.name : "#{repo.name} (#{env})",
          cap_result,
          status_check_result
        ]
      end
      puts "\n--------------------  END #{repo.name}  --------------------\n"
    end

    auditor.report

    puts "\n------- RESULTS: -------\n"
    puts status_table.render(:unicode)
  end

  private

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

  def status_check(status_url)
    return if status_url.nil?

    uri = URI(status_url)
    resp = Net::HTTP.get_response(uri)
    puts "\n**** STATUS CHECK #{status_url} returned #{resp.code}: #{resp.body} ****\n"
    resp.code == '200'
  rescue StandardError => e
    puts colorize_failure("!!!!!!!!! STATUS CHECK #{status_url} RAISED #{e.message}")
    false
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

  def status_table
    @status_table ||= TTY::Table.new(header: ['repo', 'deploy result', 'status result'])
  end
end
# rubocop:enable Metrics/ClassLength
