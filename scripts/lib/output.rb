# frozen_string_literal: true

module ScriptOutput
  module_function

  def error(message, context: nil)
    prefix = context ? "[#{context}] " : ''
    warn "::error::#{prefix}#{message}"
  end

  def fail!(message, prefix: nil)
    warn([prefix, message].compact.join(': '))
    exit 1
  end

  def usage!(message)
    fail!(message)
  end
end
