# frozen_string_literal: true

require 'net/http'

# Service class for checking status URLs
class StatusChecker
  def self.check(environment:, repo:)
    new(environment: environment, repo: repo).check_status
  end

  attr_reader :environment, :repo

  def initialize(environment:, repo:)
    @environment = environment
    @repo = repo
  end

  def check_status
    configured_url = repo.status&.public_send(environment)
    if configured_url != server_url
      puts "configured url for #{repo.name} (#{environment}): #{configured_url}"
      puts "code url for #{repo.name} (#{environment}): #{server_url}"
    end
    # return if configured_url.nil?

  #   uri = URI(status_url)
  #   resp = Net::HTTP.get_response(uri)
  #   puts "\n**** STATUS CHECK #{status_url} returned #{resp.code}: #{resp.body} ****\n"
  #   resp.code == '200'
  # rescue StandardError => e
  #   puts colorize_failure("!!!!!!!!! STATUS CHECK #{status_url} RAISED #{e.message}")
  #   false
  end

  private

  def server_url
    server = File.readlines("config/deploy/#{environment}.rb")
                 .grep(/^server/)
                 .first
                 .match(/server '(.+?)'/)
                 .captures
                 .first
    "https://#{server}/status/all"
  end
end
