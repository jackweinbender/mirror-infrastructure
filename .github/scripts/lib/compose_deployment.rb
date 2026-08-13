# frozen_string_literal: true

module ComposeDeployment
  BASE_DIR = '/etc/compose-stacks'

  module_function

  def run_tag
    "#{ENV['GITHUB_RUN_ID']}-#{ENV['GITHUB_RUN_ATTEMPT']}"
  end

  def staging_path(stack)
    File.join(BASE_DIR, '.staging', "#{stack}-#{run_tag}")
  end

  def marker(stack)
    <<~MARKER
      REPOSITORY=#{ENV['GITHUB_REPOSITORY']}
      STACK_NAME=#{stack}
      COMMIT_SHA=#{ENV['GITHUB_SHA']}
      WORKFLOW_RUN_ID=#{ENV['GITHUB_RUN_ID']}
      WORKFLOW_RUN_NUMBER=#{ENV['GITHUB_RUN_NUMBER']}
      SYNCED_AT=#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}
    MARKER
  end
end
