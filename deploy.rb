#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'yaml'
require 'net/http'
require 'fileutils'
require 'auditor'

# Usage:
# ./deploy.rb stage
#
# To test SSH connections to all servers in the specified environment, first run:
# ./deploy.rb stage --checkssh

WORK_DIR = ['tmp/repos'].freeze

def update_repo(repo_dir)
  Dir.chdir(repo_dir) do
    `git fetch origin`
    `git reset --hard $(git symbolic-ref refs/remotes/origin/HEAD) 2> /dev/null`
  end
end

def create_repo(repo_dir, repo)
  FileUtils.mkdir_p repo_dir
  puts "creating #{repo}"
  Dir.chdir(repo_dir) do
    `git clone --depth=5 git@github.com:#{repo}.git .`
    unless $?.success?
      warn "Error, while running git clone"
      exit(1)
    end
  end
end

def update_or_create_repo(repo_dir, repo)
  if File.exist? repo_dir
    update_repo(repo_dir)
  else
    create_repo(repo_dir, repo)
  end
end

def deploy(stage)
  IO.popen({ 'SKIP_BUNDLE_AUDIT' => 'true' }, "bundle exec cap #{stage} deploy") do |f|
    loop do
      puts f.readline
    rescue EOFError
      break
    end
  end
  $?.success?
end

def status_check(status_url)
  uri = URI(status_url)
  resp = Net::HTTP.get_response(uri)
  puts "Status check #{status_url} returned #{resp.code}: #{resp.body}"
  resp.code == '200'
rescue StandardError => e
  puts "Status check #{status_url} raised #{e.message}"
  false
end

def repo_infos
  YAML.load_stream(File.open('repos.yml'))
end

def repo_names
  repo_infos.map { |repo_info| repo_info['repo'] }
end

# Comment out where we ask what branch to deploy. We always deploy to the default branch (master for most, main for some)
def comment_out_branch_prompt!
  text = File.read('config/deploy.rb')
  text.gsub!(/(?=ask :branch)/, '# ')
  File.write('config/deploy.rb', text)
end

stage = ARGV[0]
unless %w[stage qa prod].include?(stage)
  warn 'Usage:'
  warn "  #{$PROGRAM_NAME} <stage>"
  warn "\n  stage must be one of \"stage\",\"qa\",\"prod\"\n\n"
  exit
end

ssh_check = ARGV[1] == '--checkssh'

auditor = Auditor.new

puts "repos to #{ssh_check ? 'ssh_check' : 'deploy'}: #{repo_names.join(', ')}"

deploys = {}
repo_infos.each do |repo_info|
  repo = repo_info['repo']
  repo_dir = File.join(WORK_DIR, repo)
  update_or_create_repo(repo_dir, repo)
  auditor.audit(repo: repo, dir: repo_dir) unless ssh_check
  Dir.chdir(repo_dir) do
    puts "Installing gems for #{repo_dir}"
    `bundle install`
    if ssh_check
      puts "running 'cap #{stage} ssh_check' for #{repo_dir}"
      `bundle exec cap #{stage} ssh_check`
    else
      puts "###\nDeploying #{repo_dir}..."
      comment_out_branch_prompt!
      deploys[repo] = { cap_result: deploy(stage) }
      puts "...Deployed #{repo_dir}; result: #{deploys[repo]}\n###"
      status_url = repo_info.fetch('status', {})[stage]
      next unless deploys[repo][:cap_result] && status_url

      deploys[repo].merge!({ status_check_result: status_check(status_url) })
    end
  end
end

unless ssh_check
  puts "\n\n------- BUNDLE AUDIT SECURITY REPORT -------"
  auditor.report

  puts "\n\n------- STATUS CHECK (https::/xxx/status) RESULTS AFTER DEPLOY -------\n"
  deploys.each do |repo, deploy_result|
    cap_result = deploy_result[:cap_result] ? 'success' : 'FAILED'
    status_check_result = case deploy_result[:status_check_result]
      when nil
        'N/A'
      when true
        'success'
      else
        'FAILED'
      end
    puts "#{repo}\n => 'cap #{stage} deploy' result: #{cap_result}\n => status check result:      #{status_check_result}"
  end
  puts "\n------- END STATUS CHECK RESULTS -------\n"
end
