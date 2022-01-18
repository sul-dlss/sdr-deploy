# frozen_string_literal: true

# Service class for checking Cocina versions
class CocinaChecker
  def self.check
    new.check_cocina
  end

  def check_cocina
    gem_filename = 'Gemfile.lock'
    repo_names = repos.map(&:name)
    puts "repos to Cocina check: #{repo_names.join(', ')}"
    version_map = Dir["#{base_directory}**/#{gem_filename}"].filter_map do |lockfile_path|
      cached_repo_name = lockfile_path.gsub(base_directory, '').gsub(gem_filename, '').chomp('/')
      next unless repo_names.include? cached_repo_name # skip any cached repo not found in the settings.yml file

      cocina_models_version = cocina_version_from(lockfile_path)
      next if cocina_models_version.empty?

      [project_name_for(lockfile_path), cocina_models_version]
    end.to_h

    unique_values = group_by_unique_values(version_map)
    puts '------- COCINA REPORT -------'
    puts 'Found these versions of cocina in use:'
    unique_values.sort.each do |version, repos|
      puts "\t#{version}"
      repos.sort.each do |repo|
        puts "\t\t#{repo}"
      end
    end

    # `true` is the happy path; `false` means dragons
    unique_values.size <= 1
  end

  private

  def repos
    @repos ||= Settings.repositories
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
end
