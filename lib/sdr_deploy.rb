# frozen_string_literal: true

require 'bundler/setup'
require 'byebug'
require 'config'
require 'open3'
require 'parallel'
require 'pastel'
require 'thor'
require 'tty-progressbar'
require 'tty-prompt'
require 'tty-table'

Config.load_and_set_settings(
  Config.setting_files('config', 'local')
)

# Common methods
# rubocop: disable Metrics/MethodLength
# rubocop: disable Metrics/AbcSize
def within_project_dir(repo:, environment: nil, &block)
  results = []

  Dir.chdir(RepoUpdater.new(repo: repo).repo_dir) do
    # NOTE: This is how we execute commands in the project-specific bundler
    #       context, rather than sdr-deploy's bundler context. We want *most* of
    #       the behavior provided by `Bundler.with_unbundled_env`, except we
    #       still need the ContribSys credentials in order to be able to install
    #       sidekiq-pro into the bundle for projects using sidekiq-pro.
    contribsys_credentials = ENV['BUNDLE_GEMS__CONTRIBSYS__COM']
    Bundler.with_unbundled_env do
      ENV['BUNDLE_GEMS__CONTRIBSYS__COM'] = contribsys_credentials
      results << block.call(environment)

      # Some of our apps use non-standard envs
      if environment == 'qa' && repo.non_standard_qa_envs
        repo.non_standard_qa_envs.each { |env| results << block.call(env) }
      end

      if environment == 'prod' && repo.non_standard_prod_envs
        repo.non_standard_prod_envs.each { |env| results << block.call(env) }
      end

      results
    end
  end
end
# rubocop: enable Metrics/MethodLength
# rubocop: enable Metrics/AbcSize

def colorize_failure(string)
  pastel.white.on_bright_red.bold(string)
end

def colorize_success(string)
  pastel.green.on_bright_black.bold(string)
end

def pastel
  @pastel ||= Pastel.new
end

Dir['./lib/*.rb'].each { |f| require f }
