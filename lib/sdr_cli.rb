# frozen_string_literal: true

# SDR command-line interface
class SdrCLI < Thor
  def self.exit_on_failure?
    true
  end

  no_commands do
    def check_control_master(skip)
      return if skip
      return if system("ssh -O check #{Settings.control_master_host}", err: File::NULL)

      say('Control master not detected. Please start a control master session.')
      exit
    end
  end

  option :skip_update,
         type: :boolean,
         default: false,
         desc: 'Skip refreshing the local git repository cache',
         aliases: '-s'
  option :tag,
         type: :string,
         desc: 'Check cocina version in the given tag or branch instead of the default branch',
         aliases: ['-t', '--branch']
  desc 'check_cocina', 'Check for Cocina data model mismatches'
  def check_cocina
    repositories = Settings.repositories.select(&:cocina_models_update)
    RepoUpdater.update(repos: repositories) unless options[:skip_update]
    CocinaChecker.check(repos: repositories, tag: options[:tag])
  end

  desc 'tag SUBCOMMAND TAG_NAME', 'Create, delete, or verify a git tag named TAG_NAME'
  subcommand 'tag', GitTagCLI

  option :only,
         type: :array,
         default: [],
         desc: 'Check connections only to these services'
  option :except,
         type: :array,
         default: [],
         desc: 'Check connections except for these services'
  option :skip_update,
         type: :boolean,
         default: false,
         desc: 'Skip refreshing the local git repository cache',
         aliases: '-s'
  option :environment,
         required: true,
         enum: ::Settings.supported_envs.keys.map(&:to_s),
         desc: 'Check connections in the given environment',
         aliases: '-e'
  option :skip_control_master,
         type: :boolean,
         default: false,
         desc: 'Skip checking for an active SSH controlmaster connection'
  desc 'check_ssh', 'Check SSH connections'
  def check_ssh
    raise Thor::Error, 'Use only one of --only or --except' if options[:only].any? && options[:except].any?

    check_control_master(options[:skip_control_master])

    repositories = if options[:only].any?
                     Settings.repositories.select { |repo| options[:only].include?(repo.name) }
                   elsif options[:except].any?
                     Settings.repositories.reject { |repo| options[:except].include?(repo.name) }
                   else
                     Settings.repositories
                   end

    # Do not prune repos if operating on a subset of repos else legitimate current repos get unnecessarily pruned
    RepoUpdater.update(repos: repositories, prune: options.slice(:only, :except).none?) unless options[:skip_update]
    SshChecker.check(environment: options[:environment], repos: repositories)
  end

  option :only,
         type: :array,
         default: [],
         desc: 'Deploy only these services'
  option :except,
         type: :array,
         default: [],
         desc: 'Deploy all except these services'
  option :skip_non_cocina,
         type: :boolean,
         default: false,
         desc: 'Deploy only services depending on new Cocina models releases',
         aliases: '-c'
  option :before_command,
         type: :string,
         desc: 'Run this command on each host before deploying',
         aliases: '-b'
  option :tag,
         type: :string,
         desc: 'Deploy the given tag or branch instead of the default branch',
         aliases: ['-t', '--branch']
  option :skip_update,
         type: :boolean,
         default: false,
         desc: 'Skip refreshing the local git repository cache',
         aliases: '-s'
  option :environment,
         required: true,
         enum: Settings.supported_envs.keys.map(&:to_s),
         desc: 'Deployment environment',
         aliases: '-e'
  option :skip_control_master,
         type: :boolean,
         default: false,
         desc: 'Skip checking for active SSH control master connection'
  desc 'deploy', 'Deploy services to a given environment'
  def deploy
    raise Thor::Error, 'Use only one of --only or --except' if options[:only].any? && options[:except].any?

    check_control_master(options[:skip_control_master])

    repositories = if options[:skip_non_cocina]
                     Settings.repositories.select(&:cocina_models_update)
                   else
                     Settings.repositories
                   end

    if options[:only].any?
      repositories.select! { |repo| options[:only].include?(repo.name) }
    elsif options[:except].any?
      repositories.reject! { |repo| options[:except].include?(repo.name) }
    end

    repositories.reject! { |repo| Array(repo.skip_envs).include?(options[:environment]) }

    # Do not prune repos if operating on a subset of repos else legitimate current repos get unnecessarily pruned
    RepoUpdater.update(repos: repositories, prune: options.slice(:only, :except, :skip_non_cocina).none?) unless options[:skip_update]
    abort 'ABORTING: due to cocina-models version divergence' unless CocinaChecker.check(repos: Settings.repositories.select(&:cocina_models_update), tag: options[:tag])

    Deployer.deploy(
      environment: options[:environment],
      repos: repositories,
      tag: options[:tag],
      before_command: options[:before_command]
    )
  end

  option :only,
         type: :array,
         default: [],
         desc: 'Update the cache only for these repos'
  option :except,
         type: :array,
         default: [],
         desc: 'Update the cache except for these repos'
  desc 'refresh_repos', 'Refresh the local git repository cache'
  def refresh_repos
    RepoUpdater.update(repos: Settings.repositories, prune: options.slice(:only, :except).none?)
  end

  desc 'audit_repos', 'Run bundle audit on repositories in the local git cache'
  def audit_repos
    RepoAuditor.audit(repos: Settings.repositories)
  end
end
