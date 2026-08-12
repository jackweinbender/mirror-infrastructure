#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'tempfile'

ROOT = File.expand_path('../..', __dir__)
STACKS_DIR = File.join(ROOT, 'compose-stacks')
NAME_PATTERN = /\A[a-z0-9][a-z0-9_-]*\z/
DISCOVER_SCRIPT = File.join(ROOT, '.github/scripts/discover-deploy-hosts.rb')
MERGE_SCRIPT = File.join(ROOT, '.github/scripts/merge-dotenv.rb')

def fail_preflight(message)
  warn "preflight: #{message}"
  exit 1
end

def command(program, *args, **options)
  stdout, stderr, status = Open3.capture3(program, *args, **options)
  raise(stderr.strip.empty? ? "#{program} exited with #{status.exitstatus}" : stderr.strip) unless status.success?
  stdout
end

def parse_inventory
  JSON.parse(command('ruby', DISCOVER_SCRIPT, File.join(ROOT, 'ansible/inventory.yaml')))
rescue StandardError => e
  fail_preflight("could not read deploy hosts: #{e.message}")
end

def merged_env(shared, assignment)
  command('ruby', MERGE_SCRIPT, shared, assignment)
rescue StandardError => e
  fail_preflight("dotenv validation failed for #{assignment}: #{e.message}")
end

def validate_compose(stack, host, compose, env_text)
  representative = env_text.gsub(/op:\/\/[^\s]+/, 'example-secret')
  env_file = Tempfile.new(["compose-#{stack}-#{host}-", '.env'])
  env_file.write(representative)
  env_file.flush
  env_file.chmod(0o600)
  begin
    command('docker', 'compose', '--project-name', stack, '--env-file', env_file.path, '-f', compose, 'config', '--quiet', err: [:child, :out])
  rescue StandardError => e
    fail_preflight("Compose validation failed for #{stack}/#{host}: #{e.message}")
  ensure
    env_file.close!
  end
end

hosts = parse_inventory
host_ids = hosts.to_h { |host| [host['id'], true] }
stacks = []

Dir.each_child(STACKS_DIR) do |stack|
  stack_dir = File.join(STACKS_DIR, stack)
  next unless File.directory?(stack_dir) && stack != 'docker-host'

  fail_preflight("invalid stack name: #{stack}") unless NAME_PATTERN.match?(stack)
  compose = File.join(stack_dir, 'docker-compose.yaml')
  fail_preflight("application stack #{stack} has no docker-compose.yaml") unless File.file?(compose)

  deployments = File.join(stack_dir, 'deployments')
  shared = File.join(deployments, '_shared.env')
  fail_preflight("#{shared} is not a regular file") if File.exist?(shared) && !File.file?(shared)

  if File.directory?(deployments)
    Dir.each_child(deployments) do |filename|
      next if filename == '_shared.env'

      assignment = File.join(deployments, filename)
      fail_preflight("invalid deployment file: #{assignment}") unless File.file?(assignment) && filename.end_with?('.env')
      host = filename.delete_suffix('.env')
      fail_preflight("invalid deployment host filename: #{filename}") unless NAME_PATTERN.match?(host) && host != 'docker-host'
      fail_preflight("unknown deployment host #{host} in #{assignment}") unless host_ids.key?(host)
      validate_compose(stack, host, compose, merged_env(shared, assignment))
    end
  end
  stacks << stack
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
