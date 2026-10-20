#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'

require_relative '../lib/commands'
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

class StackInventoryTest < LibTest
  def setup
    @inventory = <<~YAML
      all:
        children:
          stack_hosts:
            children:
              deployment_hosts:
                hosts:
                  zeta.example: {}
                  lxc-docker-core0.example: {}
                  controller.example: {}
    YAML
  end

  def test_returns_exact_short_ids_from_the_single_deployment_group
    with_file(@inventory) do |file|
      assert_equal %w[controller lxc-docker-core0 zeta], StackInventory.deployment_host_ids(file)
  end
  end

  def test_rejects_duplicate_short_host_ids
    duplicate = @inventory.sub('controller.example: {}', 'zeta.other.example: {}')
    with_file(duplicate) do |file|
      error = assert_raises(ArgumentError) { StackInventory.deployment_host_ids(file) }
      assert_match(/not unique/, error.message)
    end
  end

  def test_rejects_invalid_short_host_ids
    invalid = @inventory.sub('zeta.example: {}', 'bad name.example: {}')
    with_file(invalid) do |file|
      assert_raises(ArgumentError) { StackInventory.deployment_host_ids(file) }
    end
  end
end

class TerraformComponentsTest < LibTest
  def setup
    @manifest = %w[aws gcp cloudflare]
  end

  def test_changed_returns_all_components_for_shared_terraform_root_changes
    assert_equal @manifest, TerraformComponents.changed(@manifest, ['terraform/components.json'])
    assert_equal @manifest, TerraformComponents.changed(@manifest, ['terraform/providers.tf'])
  end

  def test_changed_returns_unique_components_for_component_paths
    paths = ['terraform/aws/main.tf', 'terraform/aws/variables.tf', 'terraform/cloudflare/main.tf', 'docs/reference/README.md']
    assert_equal %w[aws cloudflare], TerraformComponents.changed(@manifest, paths)
  end

  def test_changed_ignores_unrelated_paths
    assert_empty TerraformComponents.changed(@manifest, ['.github/workflows/terraform.yaml', 'README.md', 'terraform/README.md'])
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


class ScriptCommandsTest < LibTest

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
