# frozen_string_literal: true

module DeploymentStrategies
  # Executes Kamal from the selected target in the cached repository.
  class Kamal < DeploymentStrategy
    REQUIRED_EXECUTABLES = %w[bundle docker ssh ssh-add ssh-agent ssh-keygen vault].freeze

    def self.preflight!
      missing = REQUIRED_EXECUTABLES.reject { |executable| executable_available?(executable) }
      raise Thor::Error, "Missing commands required for Kamal: #{missing.join(', ')}" if missing.any?

      unless system('docker', 'buildx', 'version', out: File::NULL, err: File::NULL)
        raise Thor::Error, 'Kamal deployments require the Docker Buildx plugin'
      end

      vault_authenticated = system('vault', 'token', 'lookup', out: File::NULL, err: File::NULL) ||
                            system('vault', 'login', '-method=oidc')
      raise Thor::Error, 'Unable to authenticate to Vault for the Kamal deployment' unless vault_authenticated
    end

    def self.executable_available?(executable)
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |directory|
        File.executable?(File.join(directory, executable))
      end
    end
    private_class_method :executable_available?

    def deploy(environment:, before_command: nil)
      checkout_target
      ensure_bundle!
      deploy_from_repo(environment, before_command)
    rescue StandardError => e
      [false, "#{e.class}: #{e.message}\n"]
    end

    def check_ssh(environment:)
      capture_command('bin/kamal-otk', environment, 'server', 'exec', 'true')
    end

    private

    def checkout_target
      run_command('git', '-C', repo_dir, 'checkout', '--quiet', '--detach', target || 'HEAD')
    end

    def deploy_from_repo(environment, before_command)
      status, output = run_before_command(environment, before_command)
      return [false, output] unless status

      deploy_status, deploy_output = capture_command('bin/kamal-otk', environment, 'deploy')
      [deploy_status, output + deploy_output]
    end

    def run_before_command(environment, before_command)
      return [true, ''] unless before_command

      capture_command('bin/kamal-otk', environment, 'server', 'exec', before_command)
    end

    def ensure_bundle!
      status, = capture_command('bundle', 'check')
      run_command('bundle', 'install') unless status
    end
  end
end
