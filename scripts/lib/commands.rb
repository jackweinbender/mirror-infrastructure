# frozen_string_literal: true

require 'open3'

module ScriptCommands
  module_function

  def capture(program, *args, **options)
    stdout, stderr, status = Open3.capture3(program, *args, **options)
    return stdout if status.success?

    raise(stderr.strip.empty? ? "#{program} exited with #{status.exitstatus}" : stderr.strip)
  end
end
