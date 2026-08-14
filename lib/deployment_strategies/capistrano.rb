# frozen_string_literal: true

module DeploymentStrategies
  # Executes the established Capistrano deployment workflow.
  class Capistrano < DeploymentStrategy
    def deploy(environment:, before_command: nil)
      status, output = run_before_command(environment, before_command)
      return [false, output] unless status

      deploy_status, deploy_output = deploy_command(environment)
      [deploy_status, output + deploy_output]
    rescue StandardError => e
      [false, "#{e.class}: #{e.message}\n"]
    end

    def check_ssh(environment:)
      capture_command({}, 'bundle', 'exec', 'cap', environment, 'ssh_check')
    end

    private

    def deploy_command(environment)
      set_deploy_target!
      capture_command(
        { 'SKIP_BUNDLE_AUDIT' => 'true' },
        'bundle', 'exec', 'cap', environment, 'deploy'
      )
    end

    def run_before_command(environment, before_command)
      return [true, ''] unless before_command

      capture_command(
        {},
        'bundle', 'exec', 'cap', environment, "remote_execute[#{before_command}]"
      )
    end

    def set_deploy_target!
      if target
        TTY::File.replace_in_file(
          'config/deploy.rb', /^ask :branch.+$/, "set :branch, '#{target}'", verbose: false
        )
      else
        TTY::File.replace_in_file('config/deploy.rb', /ask :branch/, 'set :branch', verbose: false)
      end
    end
  end
end
