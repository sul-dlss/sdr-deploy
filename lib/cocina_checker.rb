# frozen_string_literal: true

# Service class for checking Cocina versions
class CocinaChecker
  # when tag is nil, use default branch
  def self.check(repos:, tag: nil)
    new(tag:, repos:).check_cocina
  end

  attr_reader :tag, :repos

  # when tag is nil, use default branch
  def initialize(repos:, tag: nil)
    @tag = tag
    @repos = repos
    # the following raises an error if the tag isn't present in all repos
    Deployer.new(tag:, repos:, environment: nil).ensure_tag_present_in_all_repos! if tag
  end

  def check_cocina
    render_markdown('***')
    render_markdown("# Checking Cocina version (#{tag || 'default branch'})")

    unique_values = group_by_unique_values(version_map)
    unique_values.sort.each do |version, repos|
      report_table << [
        version,
        repos.sort.join("\n")
      ]
    end

    if unique_values.empty?
      render_markdown('## No repositories depend on Cocina')
    else
      puts report_table.render(:unicode, multiline: true)
    end

    # `true` is the happy path; `false` means dragons
    return true if unique_values.size <= 1

    unique_major_minors = unique_values.keys.map do |version_string|
      version_string.split('.')[0..1].join('.')
    end.uniq

    return false if unique_major_minors.size > 1

    TTY::Prompt.new.yes?('Found divergence in cocina-models patch-level versions. Continue with deploy?') do |prompt|
      prompt.default(true)
    end
  end

  private

  def report_table
    @report_table ||= TTY::Table.new(header: %w[version repos])
  end

  def version_map
    Dir["#{base_directory}**/Gemfile.lock"].filter_map do |lockfile_path|
      next unless repos.map(&:name).any? { |repo_name| lockfile_path.match?(repo_name) }

      switch_repo_to_tag(lockfile_path, tag) if tag
      cocina_models_version = cocina_version_from(lockfile_path)
      next if cocina_models_version.empty?

      switch_repo_to_tag(lockfile_path, nil) if tag # back to default branch

      [project_name_for(lockfile_path), cocina_models_version]
    end.to_h
  end

  def base_directory
    "#{Dir.pwd}/#{Settings.work_dir}/"
  end

  def cocina_version_from(lockfile_path)
    Bundler::LockfileParser
      .new(Bundler.read_file(lockfile_path))
      .specs
      .find { |spec| spec.name == 'cocina-models' }
      &.version
      .to_s
  end

  def project_name_for(lockfile_path)
    lockfile_path
      .delete_suffix('/Gemfile.lock')
      .delete_prefix(base_directory)
  end

  # Convert a hash that looks like:
  #   {
  #     "sul-dlss/preservation_catalog" => "0.62.0",
  #     "sul-dlss/argo" => "0.62.0",
  #     "sul-dlss/common-accessioning" => "0.62.0",
  #     "sul-dlss/was-registrar-app" => "0.62.1"
  #   }
  #
  # To:
  #   {
  #     "0.62.0" => ["sul-dlss/preservation_catalog", "sul-dlss/argo", "sul-dlss/common-accessioning"],
  #     "0.62.1" => ["sul-dlss/was-registrar-app"]
  #   }
  def group_by_unique_values(hash)
    hash
      .group_by { |_key, value| value }
      .transform_values { |value| value.map(&:first) }
  end

  # git checkout repo to the given tag/branch, or switch to default branch if none
  def switch_repo_to_tag(lockfile_path, target)
    Dir.chdir(lockfile_path.delete_suffix('/Gemfile.lock')) do
      if tag?(target)
        # it's fine for this to be a detached HEAD
        `git checkout #{target} -q -d`
      elsif branch?(target)
        `git switch -q #{target}`
      else
        `git switch -q -`
      end
    end
  end

  def branch?(target)
    return false unless target

    system("git show-ref -q --verify refs/remotes/origin/#{target}")
  end

  def tag?(target)
    return false unless target

    system("git show-ref -q --verify refs/tags/#{target}")
  end
end
