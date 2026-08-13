# frozen_string_literal: true

require 'open3'
require 'shellwords'

module ScriptCommands
  module_function

  def capture_result(program, *args, **options)
    Open3.capture3(program, *args, **options)
  end

  def capture(program, *args, **options)
    stdout, stderr, status = capture_result(program, *args, **options)
    return stdout if status.success?

    raise(stderr.strip.empty? ? "#{program} exited with #{status.exitstatus}" : stderr.strip)
  end

  def ssh(remote, command)
    system('ssh', '-o', 'BatchMode=yes', remote, command)
  end

  def quote(value)
    Shellwords.escape(value)
  end

  def write_remote(remote, command, content)
    Open3.popen3('ssh', remote, command) do |stdin, _stdout, _stderr, wait_thread|
      stdin.write(content)
      stdin.close
      wait_thread.value.success?
    end
  end

  def inject_to_remote(input, remote, command)
    environment = { 'OP_SERVICE_ACCOUNT_TOKEN' => ENV['OP_SERVICE_ACCOUNT_TOKEN'].to_s }
    Open3.pipeline([environment, 'op', 'inject', '-i', input], ['ssh', remote, command]).all?(&:success?)
  end
end
