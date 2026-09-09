# frozen_string_literal: true

require 'json'
require 'net/http'
require 'rexml/document'
require 'uri'

# Exchange an OIDC ID token for short-lived AWS and GCP credentials and shape
# them into the environment variables Terraform consumes.
#
# Crow CI does not mint ID tokens itself; the token arrives in the step as
# `OIDC_ID_TOKEN` (see .crow/terraform-oidc.yaml and terraform/oidc-crow.md).
# The HTTP exchanges below are integration boundaries and are intentionally not
# unit-tested; every pure/order/validation concern is in a tested function.
module OidcCloudAuth
  module_function

  AWS_STS_PATH = '/'
  AWS_STS_VERSION = '2011-06-15'
  GCP_STS_URL = 'https://sts.googleapis.com/token'
  DEFAULT_AWS_ROLE = 'arn:aws:iam::325498355308:role/GithubActionsRole'
  DEFAULT_REGION = 'us-east-1'
  DEFAULT_SESSION_NAME = 'CrowTerraform'
  GRANT_TYPE_TOKEN_EXCHANGE = 'urn:ietf:params:oauth:grant-type:token-exchange'
  SUBJECT_TOKEN_TYPE_JWT = 'urn:ietf:params:oauth:token-type:jwt'

  # --- Pure helpers (unit-tested) -------------------------------------------

  def aws_sts_form(id_token:, role_arn:, session_name:, duration_seconds:, version: AWS_STS_VERSION)
    URI.encode_www_form(
      'Action' => 'GetFederationToken',
      'Version' => version,
      'RoleArn' => role_arn,
      'RoleSessionName' => session_name,
      'DurationSeconds' => duration_seconds.to_i,
      'WebIdentityToken' => id_token
    )
  end

  def aws_sts_url(region)
    "https://sts.#{region}.amazonaws.com#{AWS_STS_PATH}"
  end

  def aws_environment(access_key_id:, secret_access_key:, session_token:, region:)
    {
      'AWS_ACCESS_KEY_ID' => access_key_id,
      'AWS_SECRET_ACCESS_KEY' => secret_access_key,
      'AWS_SESSION_TOKEN' => session_token,
      'AWS_DEFAULT_REGION' => region,
      'AWS_REGION' => region
    }
  end

  def gcp_exchange_form(id_token:, audience:)
    URI.encode_www_form(
      'grant_type' => GRANT_TYPE_TOKEN_EXCHANGE,
      'subject_token' => id_token,
      'subject_token_type' => SUBJECT_TOKEN_TYPE_JWT,
      'audience' => audience
    )
  end

  def gcp_environment(access_token:, expires_in:)
    env = {
      'GOOGLE_OAUTH_ACCESS_TOKEN' => access_token,
      'CLOUDSDK_AUTH_ACCESS_TOKEN' => access_token
    }
    env['GOOGLE_OAUTH_EXPIRY'] = (Time.now.to_i + expires_in.to_i).to_s if expires_in
    env
  end

  def resolve_aws_role
    ENV.fetch('AWS_ROLE_ARN', DEFAULT_AWS_ROLE)
  end

  def resolve_region
    ENV.fetch('AWS_DEFAULT_REGION', DEFAULT_REGION)
  end

  def resolve_session_name
    ENV.fetch('AWS_OIDC_SESSION_NAME', DEFAULT_SESSION_NAME)
  end

  def resolve_gcp_audience
    ENV.fetch('GCP_WORKLOAD_IDENTITY_PROVIDER', '')
  end

  def id_token(from_env: ENV)
    from_env['OIDC_ID_TOKEN'].to_s.strip
  end

  def missing_id_token?
    id_token.empty?
  end

  # --- Integration boundaries (thin; not unit-tested) -----------------------

  # Returns { 'AccessKeyId' => ..., 'SecretAccessKey' => ..., 'SessionToken' => ... }.
  def fetch_aws_credentials(id_token:, role_arn:, session_name:, region:, duration_seconds: 3600)
    body = post_form(aws_sts_url(region), aws_sts_form(id_token: id_token, role_arn: role_arn,
                                                       session_name: session_name, duration_seconds: duration_seconds))
    parse_sts_credentials(body)
  end

  # Returns the temporary Google OAuth access token for the workload identity
  # provider represented by `audience`.
  def fetch_gcp_access_token(id_token:, audience:)
    body = post_form(GCP_STS_URL, gcp_exchange_form(id_token: id_token, audience: audience),
                     'Accept' => 'application/json')
    payload = JSON.parse(body)
    payload.fetch('access_token')
  end

  # Builds the full cloud environment hash. Raises RuntimeError if any required
  # input is missing. This is the public entrypoint the CLI calls.
  def build_environment(id_token:)
    raise 'AWS_ROLE_ARN is required to request AWS credentials' if resolve_aws_role.empty?
    raise 'AWS_DEFAULT_REGION is required to request AWS credentials' if resolve_region.empty?

    region = resolve_region
    aws = fetch_aws_credentials(id_token: id_token, role_arn: resolve_aws_role,
                                session_name: resolve_session_name, region: region)
    env = aws_environment(
      access_key_id: aws.fetch('AccessKeyId'),
      secret_access_key: aws.fetch('SecretAccessKey'),
      session_token: aws.fetch('SessionToken'),
      region: region
    )

    audience = resolve_gcp_audience
    if audience.empty?
      env['OIDC_CLOUD_GCP_SKIPPED'] = 'GCP_WORKLOAD_IDENTITY_PROVIDER not set'
    else
      access_token = fetch_gcp_access_token(id_token: id_token, audience: audience)
      env.merge!(gcp_environment(access_token: access_token, expires_in: nil))
    end

    env
  end

  # --- Private ----------------------------------------------------------------

  def post_form(url, body, extra_headers = {})
    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    extra_headers.each { |key, value| request[key] = value }
    request.body = body

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end
    unless response.is_a?(Net::HTTPSuccess)
      raise "OIDC credential exchange failed: HTTP #{response.code} #{response.body.to_s[0, 300]}"
    end
    response.body
  end

  def parse_sts_credentials(xml)
    document = REXML::Document.new(xml)
    values = leaf_text(document.root)
    {
      'AccessKeyId' => values['AccessKeyId'].to_s.strip,
      'SecretAccessKey' => values['SecretAccessKey'].to_s.strip,
      'SessionToken' => values['SessionToken'].to_s.strip
    }
  end

  def leaf_text(node)
    node.elements.each_with_object({}) do |element, acc|
      if element.has_elements?
        acc.merge!(leaf_text(element))
      else
        acc[element.name] = element.text.to_s
      end
    end
  end
end