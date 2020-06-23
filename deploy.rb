#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'byebug'
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
    `git checkout config/deploy.rb`
    `git checkout master 2> /dev/null && git pull`
  end
end

def create_repo(repo_dir, repo)
  FileUtils.mkdir_p repo_dir
  puts "creating #{repo}"
  Dir.chdir(repo_dir) do
    `git clone --depth=5 git@github.com:#{repo}.git .`
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
  IO.popen({ 'SKIP_BUNDLE_AUDIT' => 'true' }, "cap #{stage} deploy") do |f|
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

# Comment out where we ask what branch to deploy. We always deploy master.
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

deploys = {}
repo_infos.each do |repo_info|
  repo = repo_info['repo']
  repo_dir = File.join(WORK_DIR, repo)
  update_or_create_repo(repo_dir, repo)
  auditor.audit(repo: repo, dir: repo_dir) unless ssh_check
  Dir.chdir(repo_dir) do
    puts "Deploying #{repo_dir}"
    `bundle install`
    if ssh_check
      `cap #{stage} ssh_check`
    else
      comment_out_branch_prompt!
      deploys[repo] = deploy(stage)
      status_url = repo_info.fetch('status', {})[stage]
      next unless deploys[repo] && status_url

      deploys[repo] = status_check(status_url)
    end
  end
end

auditor.report unless ssh_check
deploys.each { |repo, success| puts "#{repo} => #{success ? 'success' : 'failed'}" } unless ssh_check
