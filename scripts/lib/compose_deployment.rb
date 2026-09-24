# frozen_string_literal: true

module ComposeDeployment
  BASE_DIR = '/etc/compose-stacks'

  # Stacks that manage their own lifecycle and must never be reconciled by a
  # deployment pipeline they host. crow-ci is deployed on docker0-lxc, which is
  # also where the Crow agent that executes these pipelines runs: reconciling it
  # would `docker compose down` the very container running the step. Updates are
  # handled out-of-band instead.
  SELF_MANAGED_STACKS = %w[crow-ci].freeze

  module_function

  # Remove stacks that must not be reconciled by a pipeline they host. Any caller
  # that computes the list of application stacks should pass it through here so
  # the guard is applied consistently regardless of which workflow invokes it.
  def application_stacks(stacks)
    stacks - SELF_MANAGED_STACKS
  end

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
