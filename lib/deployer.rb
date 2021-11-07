# frozen_string_literal: true

require 'English'
require 'net/http'

# Service class for deploying
class Deployer
  def self.deploy(environment:)
    new(environment: environment).deploy_all
  end

  attr_reader :deploys, :environment

  def initialize(environment:)
    @environment = environment
    @deploys = {}
  end

  def deploy_all
    puts "repos to deploy: #{repos.map(&:name).join(', ')}"

    repos.each do |repo|
      puts "\n-------------------- BEGIN #{repo.name} --------------------\n"
      within_project_dir(RepoUpdater.new(repo: repo.name).repo_dir) do
        auditor.audit(repo: repo.name)
        puts "\n**** DEPLOYING #{repo.name} ****\n"
        comment_out_branch_prompt!
        deploys[repo.name] = { cap_result: deploy }
        puts "\n**** DEPLOYED #{repo.name}; result: #{deploys[repo.name]} ****\n"

        status_url = repo.status&.public_send(environment)

        next unless deploys[repo.name][:cap_result] && status_url

        deploys[repo.name].merge!({ status_check_result: status_check(status_url) })
      end
      puts "\n--------------------  END #{repo.name}  --------------------\n"
    end

    print_report!
  end

  private

  def repos
    @repos ||= Settings.repositories
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
    uri = URI(status_url)
    resp = Net::HTTP.get_response(uri)
    puts "\n**** STATUS CHECK #{status_url} returned #{resp.code}: #{resp.body} ****\n"
    resp.code == '200'
  rescue StandardError => e
    puts colorize_failure("!!!!!!!!! STATUS CHECK #{status_url} RAISED #{e.message}")
    false
  end

  # Comment out where we ask what branch to deploy. We always deploy the default
  # branch as configured in git/GitHub.
  def comment_out_branch_prompt!
    text = File.read('config/deploy.rb')
    # Forces the `git:create_release` cap task to use the HEAD ref, which allows
    # different repositories to use different default branches.
    text.gsub!(/ask :branch/, 'set :branch')
    File.write('config/deploy.rb', text)
  end

  def print_report!
    auditor.report
    puts "\n\n------- STATUS CHECK RESULTS AFTER DEPLOY -------\n"
    deploys.each do |repo, deploy_result|
      cap_result = deploy_result[:cap_result] ? colorize_success('success') : colorize_failure('FAILED')
      status_check_result = case deploy_result[:status_check_result]
                            when nil
                              colorize_success('N/A')
                            when true
                              colorize_success('success')
                            else
                              colorize_failure('FAILED')
                            end
      puts "#{repo}\n => 'cap #{environment} deploy' result: #{cap_result}"
      puts " => status check result:      #{status_check_result}"
    end
    puts "\n------- END STATUS CHECK RESULTS -------\n"
  end
end
