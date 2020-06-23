require 'open3'
class Auditor
  SUFFIX = "\nVulnerabilities found!\n"
  Error = Struct.new(:name, :advisory, :criticality, :version, :url, :title, :solution, keyword_init: true)

  def initialize
    @project_errors = {}
    @error_descriptions = {}
  end

  def audit(dir:, repo:)
    Dir.chdir(dir) do
      out, status = Open3.capture2 'bundle audit'
      return if status.success?

      errors = parse_errors(out)
      add_to_store(repo, errors)
    end
  end

  def add_to_store(repo, errors)
    @project_errors[repo] = errors.map(&:advisory)

    errors.each do |err|
      @error_descriptions[err.advisory] ||= err
    end
  end

  def report
    puts "\nErrors found:"

    @project_errors.each do |repo, errors|
      puts "#{repo}: #{errors.join(', ')}"
    end

    puts
    puts "Summary:"
    @error_descriptions.each_value do |err|
      err.to_h.each do |k,v|
        puts "#{k.capitalize}: #{v}"
      end
    end
  end

  def parse_errors(err)
    raise "unrecognized error: #{err}" unless err.end_with?(SUFFIX)
    err = err.delete_suffix(SUFFIX)
    err.split("\n\n").map do |error_str|
      Error.new(error_str.split("\n").map { |row| row.split(": ") }.to_h.transform_keys(&:downcase).transform_keys(&:to_sym))
    end
  end
end
