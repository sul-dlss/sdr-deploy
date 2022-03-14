# frozen_string_literal: true

require 'English'
require 'net/http'

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
  end

  def deploy_all
    puts "repos to deploy: #{repos.map(&:name).join(', ')}"

    repos.each do |repo|
      puts "\n-------------------- BEGIN #{repo.name} --------------------\n"
      within_project_dir(RepoUpdater.new(repo: repo.name).repo_dir) do
        puts "\n**** DEPLOYING #{repo.name} ****\n"
        set_deploy_target!
        auditor.audit(repo: repo.name)
        cap_result = deploy ? colorize_success('success') : colorize_failure('FAILED')
        puts "\n**** DEPLOYED #{repo.name}; result: #{cap_result} ****\n"

        status_check_result = case status_check(repo.status&.public_send(environment))
                              when nil
                                colorize_success('N/A')
                              when true
                                colorize_success('success')
                              else
                                colorize_failure('FAILED')
                              end
        status_table << [repo.name, cap_result, status_check_result]
      end
      puts "\n--------------------  END #{repo.name}  --------------------\n"
    end

    auditor.report

    puts "\n------- RESULTS: -------\n"
    puts status_table.render(:unicode)
  end

  private

  def ensure_tag_present_in_all_repos!
    return if repos_missing_tag.empty?

    raise "Aborting: git tag '#{tag}' is missing in these repos: #{repos_missing_tag.join(', ')}"
  end

  def repos_missing_tag
    @repos_missing_tag ||= repos.reject do |repo|
      Dir.chdir(RepoUpdater.new(repo: repo.name).repo_dir) { `git tag`.split.include?(tag) }
    end.map(&:name)
  end

  def auditor
    @auditor ||= Auditor.new
  end

  def deploy
    IO.popen({ 'SKIP_BUNDLE_AUDIT' => 'true' }, "bundle exec cap #{environment} deploy") do |f|
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
