#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tempfile'

require_relative '../lib/commands'
require_relative '../lib/compose_deployment'
require_relative '../lib/dotenv'
require_relative '../lib/inventory'
require_relative '../lib/oidc_cloud_auth'
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
      terraform_directories: %w[aws gcp],
      workflow_choices: %w[aws cloudflare]
    )

    assert_equal %w[gcp], checks['Terraform directories missing from manifest']
    assert_equal [], checks['Manifest entries missing Terraform directories']
    assert_equal %w[cloudflare], checks['Manual workflow choices missing from manifest']
    assert_equal [], checks['Manifest entries missing from manual workflow choices']
  end
end

class OidcCloudAuthTest < LibTest
  def test_aws_environment_builds_expected_variables
    environment = OidcCloudAuth.aws_environment(
      access_key_id: 'AKID', secret_access_key: 'SAK', session_token: 'ST', region: 'us-east-1'
    )
    assert_equal 'AKID', environment['AWS_ACCESS_KEY_ID']
    assert_equal 'SAK', environment['AWS_SECRET_ACCESS_KEY']
    assert_equal 'ST', environment['AWS_SESSION_TOKEN']
    assert_equal 'us-east-1', environment['AWS_DEFAULT_REGION']
    assert_equal 'us-east-1', environment['AWS_REGION']
  end

  def test_aws_sts_form_contains_required_fields
    form = uri_decode(OidcCloudAuth.aws_sts_form(
      id_token: 'jwt', role_arn: 'role', session_name: 's', duration_seconds: 3600
    ))
    assert_equal 'GetFederationToken', form['Action']
    assert_equal 'role', form['RoleArn']
    assert_equal 's', form['RoleSessionName']
    assert_equal '3600', form['DurationSeconds']
    assert_equal 'jwt', form['WebIdentityToken']
  end

  def test_aws_sts_url_uses_region_endpoint
    assert_equal 'https://sts.us-east-1.amazonaws.com/', OidcCloudAuth.aws_sts_url('us-east-1')
  end

  def test_gcp_exchange_form_sets_token_exchange_grant
    form = uri_decode(OidcCloudAuth.gcp_exchange_form(id_token: 'jwt', audience: 'pool/provider'))
    assert_equal 'urn:ietf:params:oauth:grant-type:token-exchange', form['grant_type']
    assert_equal 'urn:ietf:params:oauth:token-type:jwt', form['subject_token_type']
    assert_equal 'jwt', form['subject_token']
    assert_equal 'pool/provider', form['audience']
  end

  def test_gcp_environment_sets_oauth_access_token_and_expiry
    environment = OidcCloudAuth.gcp_environment(access_token: 'token', expires_in: 120)
    assert_equal 'token', environment['GOOGLE_OAUTH_ACCESS_TOKEN']
    assert_equal 'token', environment['CLOUDSDK_AUTH_ACCESS_TOKEN']
    assert_equal (Time.now.to_i + 120).to_s, environment['GOOGLE_OAUTH_EXPIRY']
  end

  def test_parse_sts_credentials_extracts_leaf_values
    xml = <<~XML
      <GetFederationTokenResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
        <GetFederationTokenResult><Credentials>
          <SessionToken>sess</SessionToken>
          <SecretAccessKey>secret</SecretAccessKey>
          <Expiration>2026-01-01T00:00:00Z</Expiration>
          <AccessKeyId>key</AccessKeyId>
        </Credentials></GetFederationTokenResult>
      </GetFederationTokenResponse>
    XML
    assert_equal({ 'AccessKeyId' => 'key', 'SecretAccessKey' => 'secret', 'SessionToken' => 'sess' },
                 OidcCloudAuth.parse_sts_credentials(xml))
  end

  def test_id_token_and_missing_detection
    with_environment('OIDC_ID_TOKEN' => 'jwt') do
      assert_equal 'jwt', OidcCloudAuth.id_token
      refute OidcCloudAuth.missing_id_token?
    end
    with_environment('OIDC_ID_TOKEN' => '  ') do
      assert OidcCloudAuth.missing_id_token?
    end
  end

  private

  def uri_decode(body)
    URI.decode_www_form(body).to_h
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
