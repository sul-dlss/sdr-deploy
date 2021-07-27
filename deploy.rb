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
#
# To see whether there's any inconsistency in the respective cocina-models versions used across the apps:
# ./deploy.rb stage --check-cocina # stage is ignored here, but must be provided, because arg parsing is not fancy in this script

WORK_DIR = ['tmp/repos'].freeze

def update_repo(repo_dir)
  Dir.chdir(repo_dir) do
    `git fetch origin`
    `git reset --hard $(git symbolic-ref refs/remotes/origin/HEAD)`
  end
end

def create_repo(repo_dir, repo)
  FileUtils.mkdir_p repo_dir
  puts "**** Creating #{repo}"
  Dir.chdir(repo_dir) do
    `git clone --depth=5 git@github.com:#{repo}.git .`
    unless $?.success?
      warn 'Error, while running git clone'
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
  puts "\n**** STATUS CHECK #{status_url} returned #{resp.code}: #{resp.body} ****\n"
  resp.code == '200'
rescue StandardError => e
  puts "!!!!!!!!! STATUS CHECK #{status_url} RAISED #{e.message}"
  false
end

def repo_infos
  YAML.load_stream(File.open('repos.yml'))
end

def repo_names
  repo_infos.map { |repo_info| repo_info['repo'] }
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

stage = ARGV[0]
unless %w[stage qa prod].include?(stage)
  warn 'Usage:'
  warn "  #{$PROGRAM_NAME} <stage>"
  warn "\n  stage must be one of \"stage\",\"qa\",\"prod\"\n\n"
  exit
end

mode = ARGV[1]
ssh_check = ['--checkssh', '--ssh_check', '--sshcheck'].include?(mode) # tolerance for those who forget the exact flag
check_cocina = mode == '--check-cocina'
unless (mode.nil? || ssh_check || check_cocina)
  warn "Unrecognized mode of operation: #{mode}"
  exit
end

auditor = Auditor.new

mode_display = mode ? mode.gsub('--', '') : 'deploy'
puts "repos to #{mode_display}: #{repo_names.join(', ')}"

deploys = {}
repo_infos.each do |repo_info|
  repo = repo_info['repo']
  repo_dir = File.join(WORK_DIR, repo)
  puts "\n-------------------- BEGIN #{repo} --------------------\n" unless ssh_check || check_cocina
  update_or_create_repo(repo_dir, repo)
  next if check_cocina

  auditor.audit(repo: repo, dir: repo_dir) unless ssh_check
  Dir.chdir(repo_dir) do
    puts "Installing gems for #{repo_dir}"
    `bundle install`
    if ssh_check
      puts "running 'cap #{stage} ssh_check' for #{repo_dir}"
      `bundle exec cap #{stage} ssh_check`
    else
      puts "\n**** DEPLOYING #{repo} ****\n"
      comment_out_branch_prompt!
      deploys[repo] = { cap_result: deploy(stage) }
      puts "\n**** DEPLOYED #{repo}; result: #{deploys[repo]} ****\n"

      status_url = repo_info.fetch('status', {})[stage]
      next unless deploys[repo][:cap_result] && status_url

      deploys[repo].merge!({ status_check_result: status_check(status_url) })
    end
    puts "\n--------------------  END #{repo}  --------------------\n" unless ssh_check || check_cocina
  end
end

if check_cocina
  command = "find tmp/repos/sul-dlss -path '*/Gemfile.lock'|xargs grep -h -e 'cocina-models (\\d'|sort|uniq"
  out, _err = Open3.capture2 command
  puts "\n\n------- COCINA REPORT -------"
  puts "Found these versions of cocina in use:\n#{out}\n\n"
  lines = out.split("\n")
  lines.pop # discard the most recent
  lines.each do |line|
    command = "find tmp/repos/sul-dlss -path '*/Gemfile.lock'|xargs grep -l \"#{line}\""
    out, _err = Open3.capture2 command
    puts "found #{line.strip.sub('cocina-models (', '').tr(')', '')} in the following files:"
    puts "#{out.gsub('tmp/repos/sul-dlss/', '')}\n\n"
  end
end

unless ssh_check || check_cocina
  puts "\n\n------- BUNDLE AUDIT SECURITY REPORT -------"
  auditor.report

  puts "\n\n------- STATUS CHECK RESULTS AFTER DEPLOY -------\n"
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
    puts "#{repo}\n => 'cap #{stage} deploy' result: #{cap_result}"
    puts " => status check result:      #{status_check_result}"
  end
  puts "\n------- END STATUS CHECK RESULTS -------\n"
end
