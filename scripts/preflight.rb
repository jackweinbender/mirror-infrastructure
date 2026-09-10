#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'tempfile'
require_relative 'lib/commands'
require_relative 'lib/output'

ROOT = File.expand_path('..', __dir__)
STACKS_DIR = File.join(ROOT, 'compose-stacks')
NAME_PATTERN = /\A[a-z0-9][a-z0-9_-]*\z/
DISCOVER_SCRIPT = File.join(ROOT, 'scripts/discover-deploy-hosts.rb')
MERGE_SCRIPT = File.join(ROOT, 'scripts/merge-dotenv.rb')
VALIDATE_TERRAFORM_COMPONENTS = File.join(ROOT, 'scripts/validate-terraform-components.rb')

def fail_preflight(message)
  ScriptOutput.fail!(message, prefix: 'preflight')
end

def validate_terraform_components
  ScriptCommands.capture('ruby', VALIDATE_TERRAFORM_COMPONENTS, chdir: ROOT)
rescue StandardError => e
  fail_preflight("Terraform component validation failed: #{e.message}")
end

def parse_inventory
  JSON.parse(ScriptCommands.capture('ruby', DISCOVER_SCRIPT, File.join(ROOT, 'ansible/inventory.yaml')))
rescue StandardError => e
  fail_preflight("could not read deploy hosts: #{e.message}")
end

def merged_env(shared, assignment)
  ScriptCommands.capture('ruby', MERGE_SCRIPT, shared, assignment)
rescue StandardError => e
  fail_preflight("dotenv validation failed for #{assignment}: #{e.message}")
end

def validate_compose(stack, host, compose, overlay, env_text)
  representative = env_text.gsub(/op:\/\/[^\s]+/, 'example-secret')
  env_file = Tempfile.new(["compose-#{stack}-#{host}-", '.env'])
  env_file.write(representative)
  env_file.flush
  env_file.chmod(0o600)
  begin
    args = ['docker', 'compose', '--project-name', stack, '--env-file', env_file.path, '-f', compose]
    args += ['-f', overlay] if overlay
    ScriptCommands.capture(*args, 'config', '--quiet', err: [:child, :out])
  rescue StandardError => e
    fail_preflight("Compose validation failed for #{stack}/#{host}: #{e.message}")
  ensure
    env_file.close!
  end
end

validate_terraform_components
hosts = parse_inventory
host_ids = hosts.to_h { |host| [host['id'], true] }
stacks = []

Dir.each_child(STACKS_DIR) do |stack|
  stack_dir = File.join(STACKS_DIR, stack)
  next unless File.directory?(stack_dir)

  fail_preflight("invalid stack name: #{stack}") unless NAME_PATTERN.match?(stack)
  compose = File.join(stack_dir, 'docker-compose.yaml')
  compose_label = stack == 'docker-networking' ? 'platform stack' : 'application stack'
  fail_preflight("#{compose_label} #{stack} has no docker-compose.yaml") unless File.file?(compose)

  shared = File.join(stack_dir, '.env.template')
  fail_preflight("#{shared} is not a regular file") if File.exist?(shared) && !File.file?(shared)

  deployments = File.join(stack_dir, 'deployments')
  if stack == 'docker-networking'
    if File.directory?(deployments)
      Dir.each_child(deployments) do |host|
        assignment_dir = File.join(deployments, host)
        fail_preflight("invalid platform deployment entry: #{assignment_dir} is not a directory") unless File.directory?(assignment_dir)
        fail_preflight("invalid platform deployment host directory: #{host}") unless NAME_PATTERN.match?(host) && host != 'docker-networking'
        fail_preflight("unknown platform deployment host #{host} in #{assignment_dir}") unless host_ids.key?(host)
        allowed = ['.env.template', 'docker-compose.yaml']
        unexpected = Dir.children(assignment_dir) - allowed
        fail_preflight("unexpected files in platform deployment #{assignment_dir}: #{unexpected.join(', ')}") unless unexpected.empty?
      end
    end
    expected_hosts = host_ids.keys
  else
    expected_hosts = File.directory?(deployments) ? Dir.children(deployments) : []
  end

  expected_hosts.each do |host|
    assignment_dir = File.join(deployments, host)
    if stack != 'docker-networking'
      fail_preflight("invalid deployment entry: #{assignment_dir} is not a directory") unless File.directory?(assignment_dir)
      fail_preflight("invalid deployment host directory: #{host}") unless NAME_PATTERN.match?(host) && host != 'docker-networking'
      fail_preflight("unknown deployment host #{host} in #{assignment_dir}") unless host_ids.key?(host)
    end

    assignment = File.join(assignment_dir, '.env.template')
    if stack == 'docker-networking'
      fail_preflight("invalid platform env template: #{assignment}") if File.exist?(assignment) && !File.file?(assignment)
    else
      fail_preflight("missing deployment env template: #{assignment}") unless File.file?(assignment)
    end
    overlay = File.join(assignment_dir, 'docker-compose.yaml')
    fail_preflight("invalid deployment overlay: #{overlay}") if File.exist?(overlay) && !File.file?(overlay)
    overlay = nil unless File.file?(overlay)
    validate_compose(stack, host, compose, overlay, merged_env(shared, assignment))
  end

  stacks << stack unless stack == 'docker-networking'
end

fail_preflight('no application Compose stacks found') if stacks.empty?
output = { 'hosts' => hosts, 'stacks' => stacks.sort }
if (github_output = ENV['GITHUB_OUTPUT'])
  File.open(github_output, 'a') do |file|
    file.puts "hosts=#{JSON.generate(output['hosts'])}"
    file.puts "stacks=#{JSON.generate(output['stacks'])}"
  end
end
puts JSON.generate(output)
