# frozen_string_literal: true

# Service class for executing commands and barfing on errors
class ErrorEmittingExecutor
  def self.execute(command, exit_on_error: false)
    _out, err, status = Open3.capture3(command)
    return if status.success?

    warn err
    exit(1) if exit_on_error
  end
end
