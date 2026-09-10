#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tempfile'

require_relative '../lib/commands'
require_relative '../lib/compose_deployment'
require_relative '../lib/dotenv'
require_relative '../lib/inventory'
require_relative '../lib/output'
require_relative '../lib/terraform_components'

class LibTest < Minitest::Test
  private

  def with_file(content)
    Tempfile.create('lib-test') do |file|
      file.write(content)
      file.flush
      yield file.path
    end
  end

  def with_environment(values)
    previous = values.to_h { |key, _value| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    values.each do |key, _value|
      previous[key].nil? ? ENV.delete(key) : ENV[key] = previous[key]
    end
  end
end

class DotenvTest < LibTest
  def test_parse_ignores_comments_supports_export_and_unquotes_values
    with_file("# comment — UTF-8\nexport API_KEY = \"secret value\"\nEMPTY=\nPLAIN=value=with-equals\n") do |file|
      assert_equal(
        { 'API_KEY' => 'secret value', 'EMPTY' => '', 'PLAIN' => 'value=with-equals' },
        Dotenv.parse(file)
      )
    end
  end

  def test_merge_applies_files_in_order_and_ignores_missing_files
    with_file("SHARED=first\nOVERRIDE=shared\n") do |shared|
      with_file("OVERRIDE=host\nHOST_ONLY=value\n") do |host|
        assert_equal(
          { 'SHARED' => 'first', 'OVERRIDE' => 'host', 'HOST_ONLY' => 'value' },
          Dotenv.merge([shared, '/does/not/exist', host])
        )
      end
    end
  end

  def test_parse_rejects_malformed_lines_and_invalid_keys
    with_file("MISSING_SEPARATOR\n") { |file| assert_raises(RuntimeError) { Dotenv.parse(file) } }
    with_file("NOT-VALID=value\n") { |file| assert_raises(RuntimeError) { Dotenv.parse(file) } }
    with_file("QUOTED=\"unterminated\n") { |file| assert_raises(RuntimeError) { Dotenv.parse(file) } }
  end

end

class DeployInventoryTest < LibTest
  def setup
    @inventory = <<~YAML
      workloads:
        hosts:
          zeta.example:
            ansible_host: 10.0.0.2
            host_roles:
              - deploy
          alpha.example:
            host_roles:
              - deploy
          worker.example:
            host_roles:
              - worker
    YAML
  end

  def test_selects_deploy_hosts_with_addresses_and_sorts_them
    with_file(@inventory) do |file|
      assert_equal(
        [
          { 'id' => 'alpha', 'address' => 'alpha.example' },
          { 'id' => 'zeta', 'address' => '10.0.0.2' }
        ],
        DeployInventory.deploy_hosts(file)
      )
    end
  end

  def test_host_filter_selects_one_deploy_host
    with_file(@inventory) do |file|
      assert_equal(
        [{ 'id' => 'zeta', 'address' => '10.0.0.2' }],
        DeployInventory.deploy_hosts(file, selected_host: 'zeta')
      )
    end
  end

  def test_rejects_unknown_host_filter_and_reserved_host
    with_file(@inventory) do |file|
      error = assert_raises(SystemExit) { DeployInventory.deploy_hosts(file, selected_host: 'missing') }
      assert_equal 1, error.status
    end

    reserved = @inventory.sub('zeta.example:', 'docker-networking.example:')
    with_file(reserved) do |file|
      assert_raises(SystemExit) { DeployInventory.deploy_hosts(file) }
    end
  end
end

class TerraformComponentsTest < LibTest
  def setup
    @manifest = %w[aws gcp cloudflare]
  end

  def test_changed_returns_all_components_for_root_changes
    assert_equal @manifest, TerraformComponents.changed(@manifest, ['.github'])
  end

  def test_changed_returns_unique_components_for_component_paths
    paths = ['terraform/aws/main.tf', 'terraform/aws/variables.tf', 'terraform/cloudflare/main.tf', 'docs/reference/README.md']
    assert_equal %w[aws cloudflare], TerraformComponents.changed(@manifest, paths)
  end

  def test_consistency_checks_report_each_mismatch
    checks = TerraformComponents.consistency_checks(
      manifest: %w[aws],
      terraform_directories: %w[aws gcp]
    )

    assert_equal %w[gcp], checks['Terraform directories missing from manifest']
    assert_equal [], checks['Manifest entries missing Terraform directories']

  end
end

class ComposeDeploymentTest < LibTest
  def test_staging_path_uses_run_identity
    with_environment('GITHUB_RUN_ID' => '123', 'GITHUB_RUN_ATTEMPT' => '2') do
      assert_equal '/etc/compose-stacks/.staging/traefik-123-2', ComposeDeployment.staging_path('traefik')
    end
  end

  def test_marker_contains_deployment_identity
    environment = {
      'GITHUB_REPOSITORY' => 'owner/repository',
      'GITHUB_SHA' => 'abc123',
      'GITHUB_RUN_ID' => '123',
      'GITHUB_RUN_NUMBER' => '45'
    }

    with_environment(environment) do
      marker = ComposeDeployment.marker('traefik')
      assert_includes marker, "REPOSITORY=owner/repository\n"
      assert_includes marker, "STACK_NAME=traefik\n"
      assert_includes marker, "COMMIT_SHA=abc123\n"
      assert_match(/^SYNCED_AT=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/, marker.lines.last.chomp)
    end
  end
end

class ScriptCommandsTest < LibTest
  def test_quote_shell_escapes_values
    assert_equal 'value\\ with\\ spaces', ScriptCommands.quote('value with spaces')
    assert_equal "it\\'s", ScriptCommands.quote("it's")
  end

  def test_capture_returns_stdout
    assert_equal "output\n", ScriptCommands.capture('ruby', '-e', 'puts "output"')
  end

  def test_capture_raises_stderr_when_command_fails
    error = assert_raises(RuntimeError) { ScriptCommands.capture('ruby', '-e', 'warn "failed"; exit 3') }
    assert_equal 'failed', error.message
  end
end

class ScriptOutputTest < LibTest
  def test_error_formats_optional_context
    stderr = capture_io { ScriptOutput.error('failed', context: 'host/stack') }.fetch(1)
    assert_equal "::error::[host/stack] failed\n", stderr
  end

  def test_fail_exits_with_status_one_and_prefix
    stderr = capture_io do
      error = assert_raises(SystemExit) { ScriptOutput.fail!('failed', prefix: 'preflight') }
      assert_equal 1, error.status
    end.fetch(1)

    assert_equal "preflight: failed\n", stderr
  end
end
