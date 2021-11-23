# frozen_string_literal: true

require 'bundler/setup'
require 'byebug'
require 'config'
require 'open3'
require 'pastel'
require 'thor'
require 'tty-progressbar'
require 'tty-table'

Config.load_and_set_settings(
  Config.setting_files('config', 'local')
)

# Common methods
def within_project_dir(dir, &block)
  Dir.chdir(dir) do
    # NOTE: This is how we execute commands in the project-specific bundler
    #       context, rather than sdr-deploy's bundler context. We want *most* of
    #       the behavior provided by `Bundler.with_unbundled_env`, except we
    #       still need the ContribSys credentials in order to be able to install
    #       sidekiq-pro into the bundle for projects using sidekiq-pro.
    contribsys_credentials = ENV['BUNDLE_GEMS__CONTRIBSYS__COM']
    Bundler.with_unbundled_env do
      ENV['BUNDLE_GEMS__CONTRIBSYS__COM'] = contribsys_credentials
      block.call
    end
  end
end

def colorize_failure(string)
  pastel.white.on_bright_red.bold(string)
end

def colorize_success(string)
  pastel.green.on_bright_black.bold(string)
end

def pastel
  @pastel ||= Pastel.new
end

Dir['./lib/*.rb'].sort.each { |f| require f }
