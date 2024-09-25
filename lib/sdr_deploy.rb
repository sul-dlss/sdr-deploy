# frozen_string_literal: true

require 'bundler/setup'
require 'byebug'
require 'config'
require 'open3'
require 'parallel'
require 'pastel'
require 'thor'
require 'tty-file'
require 'tty-logger'
require 'tty-markdown'
require 'tty-progressbar'
require 'tty-prompt'
require 'tty-table'

Config.load_and_set_settings(
  Config.setting_files('config', 'local')
)

# Common methods
# rubocop:disable Metrics/MethodLength
def within_project_dir(repo:, environment: nil, &block)
  results = []

  Dir.chdir(RepoUpdater.new(repo:).repo_dir) do
    # NOTE: This is how we execute commands in the project-specific bundler
    #       context, rather than sdr-deploy's bundler context. We want *most* of
    #       the behavior provided by `Bundler.with_unbundled_env`, except we
    #       still need the ContribSys credentials in order to be able to install
    #       sidekiq-pro into the bundle for projects using sidekiq-pro.
    contribsys_credentials = ENV.fetch('BUNDLE_GEMS__CONTRIBSYS__COM', nil)
    Bundler.with_unbundled_env do
      ENV['BUNDLE_GEMS__CONTRIBSYS__COM'] = contribsys_credentials
      results << block.call(environment) unless repo.exclude_envs&.include?(environment)

      # Some of our apps use non-standard envs, which we deploy alongside prod
      if environment == 'prod' && repo.non_standard_envs
        repo.non_standard_envs.each { |env| results << block.call(env) }
      end

      results
    end
  end
end
# rubocop:enable Metrics/MethodLength

def light_mode?
  !!Settings.light_mode
end

def pastel
  @pastel ||= Pastel.new
end

def colorize_failure(string)
  if light_mode?
    pastel.red.on_bright_white.italic(string)
  else
    pastel.white.on_bright_red.italic(string)
  end
end

def colorize_success(string)
  if light_mode?
    pastel.green.on_bright_white.bold(string)
  else
    pastel.black.on_green.bold(string)
  end
end

LIGHT_THEME = {
  em: :italic,
  header: %i[black bold on_bright_white],
  hr: :green,
  link: %i[blue underline],
  list: :magenta,
  strong: :bold,
  table: :magenta,
  quote: :magenta,
  image: :bright_black,
  note: :magenta,
  comment: :bright_black
}.freeze

DARK_THEME = {
  em: %i[bright_yellow italic],
  header: %i[bright_cyan bold on_black],
  hr: :bright_yellow,
  link: %i[bright_yellow underline],
  list: :bright_yellow,
  strong: %i[bright_yellow bold],
  table: :bright_yellow,
  quote: :bright_yellow,
  image: :bright_black,
  note: :bright_yellow,
  comment: :bright_black
}.freeze

def render_markdown(string)
  puts TTY::Markdown.parse(string, theme: light_mode? ? LIGHT_THEME : DARK_THEME)
end

Dir['./lib/*.rb'].each { |f| require f }
