#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Thin entrypoint that exchanges an OIDC ID token for short-lived AWS and GCP
# credentials and writes them as `KEY=VALUE` lines for the workflow to source.
#
# Required environment:
#   OIDC_ID_TOKEN                 short-lived ID token for the Crow run
#   GCP_WORKLOAD_IDENTITY_PROVIDER  (optional) full pool-provider resource name
#
# Optional:
#   AWS_ROLE_ARN                  IAM role to assume (default: GithubActionsRole)
#   AWS_DEFAULT_REGION            (default: us-east-1)
#   OIDC_CLOUD_ENV_FILE           output path (default: terraform-oidc.env)
#
# If OIDC_ID_TOKEN is empty the script exits non-zero rather than inventing
# fake credentials. It never prints token/secret values, only key names.

require 'pathname'
require_relative 'lib/oidc_cloud_auth'

ROOT = File.expand_path('..', __dir__)
OUTPUT = ENV.fetch('OIDC_CLOUD_ENV_FILE', File.join(ROOT, 'terraform-oidc.env'))

begin
  token = OidcCloudAuth.id_token
  raise 'OIDC_ID_TOKEN is not set; configure an IdP per terraform/oidc-crow.md' if token.empty?

  environment = OidcCloudAuth.build_environment(id_token: token)
  lines = environment.map { |key, value| "#{key}=#{value}" }
  File.write(OUTPUT, "#{lines.join("\n")}\n")

  skipped_gcp = environment.key?('OIDC_CLOUD_GCP_SKIPPED')
  names = environment.keys.sort
  puts "Wrote #{OUTPUT} with #{names.length} variables" + (skipped_gcp ? ' (GCP skipped)' : '')
  warn '::notice:: GCP_WORKLOAD_IDENTITY_PROVIDER not set; GCP credentials skipped' if skipped_gcp
rescue StandardError => e
  warn "::error:: #{e.message}"
  exit 1
end