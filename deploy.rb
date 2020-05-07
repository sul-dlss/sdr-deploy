#!/usr/bin/env ruby

require 'byebug'

# Usage:
# ./deploy.rb stage

require 'fileutils'

WORK_DIR = ['tmp/repos']

def update_repo(repo_dir)
  Dir.chdir(repo_dir) do
    `git checkout master 2> /dev/null && git pull`
  end
end

def create_repo(repo_dir, repo)
  FileUtils.mkdir_p repo_dir
  puts "creating #{repo}"
  Dir.chdir(repo_dir) do
    `git clone --depth=5 https://github.com/#{repo}.git .`
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
  IO.popen("cap #{stage} deploy") do |f|
    while true
      begin
        puts f.readline
      rescue EOFError
        break
      end
    end
  end
  $?.success?
end

def repos
  File.readlines("repos.txt", chomp: true).reject { |file| file.start_with?('#')}
end

stage = ARGV[0]
unless %w[stage qa prod].include?(stage)
  warn "Usage:"
  warn "  #{$0} <stage>"
  warn "\n  stage must be one of \"stage\",\"qa\",\"prod\"\n\n"
  exit
end

deploys = {}
repos.each do |repo|
  repo_dir = File.join(WORK_DIR, repo)
  update_or_create_repo(repo_dir, repo)
  Dir.chdir(repo_dir) do
    puts "Deploying #{repo_dir}"
    `bundle install`
    # Comment out where we ask what branch to deploy. We always deploy master.
    `sed -i '' 's/^\\(ask :branch.*\\)/#\\1/g' config/deploy.rb`
    deploys[repo] = deploy(stage)
    `git checkout config/deploy.rb`
  end
end

deploys.each { |repo, success| puts "#{repo} => #{success ? 'success' : 'failed'}" }
