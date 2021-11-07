# frozen_string_literal: true

# Audit for gemfile vulns
class Auditor
  SUFFIX = "\nVulnerabilities found!\n"
  Error = Struct.new(:name, :advisory, :criticality, :version, :url, :title, :solution, :cve, :ghsa, keyword_init: true)

  def initialize
    @project_errors = {}
    @error_descriptions = {}
  end

  def audit(repo:)
    out, status = Open3.capture2 'bundle exec bundle audit'
    return if status.success?

    errors = parse_errors(out)
    add_to_store(repo, errors)
  end

  def add_to_store(repo, errors)
    @project_errors[repo] = errors.map(&:advisory)

    errors.each do |err|
      @error_descriptions[err.advisory] ||= err
    end
  end

  def report
    puts "\n\n------- BUNDLE AUDIT SECURITY REPORT -------"
    if @project_errors.empty?
      puts colorize_success('No bundle security vulns found!')
      return
    end

    puts colorize_failure("\nVulnerabilities found:\n")

    @project_errors.each do |repo, errors|
      puts "#{repo}: #{errors.join(', ')}"
    end

    puts
    puts colorize_failure('CVE Details:')
    @error_descriptions.each_value do |err|
      puts
      err.to_h.each do |k, v|
        puts "#{k.capitalize}: #{v}"
      end
    end
  end

  def parse_errors(err)
    raise "!!!!!!!!! UNRECOGNIZED ERROR: #{err}" unless err.end_with?(SUFFIX)

    err = err.delete_suffix(SUFFIX)
    err.split("\n\n").map do |error_str|
      Error.new(error_str.split("\n").map do |row|
                  row.split(': ')
                end.to_h.transform_keys(&:downcase).transform_keys(&:to_sym))
    rescue ArgumentError
      puts colorize_failure("!!!!!!!!! PROBLEM PUTTING ERROR INTO OUR ERROR STRUCT: #{error_str.inspect}")
    end
  end
end
