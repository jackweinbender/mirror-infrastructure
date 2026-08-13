#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'tempfile'
require_relative 'lib/commands'
require_relative 'lib/compose_deployment'
require_relative 'lib/output'

ssh_command = ScriptCommands.method(:ssh)
quote = ScriptCommands.method(:quote)
inject_to_remote = ScriptCommands.method(:inject_to_remote)
write_remote = ScriptCommands.method(:write_remote)

host_id, host_address, stacks_json = ARGV
ScriptOutput.usage!('usage: reconcile-host.rb HOST_ID HOST_ADDRESS STACKS_JSON') unless host_id && host_address && stacks_json

remote = "#{ENV.fetch('DOCKER_USER', 'deploy')}@#{host_address}"
base = ComposeDeployment::BASE_DIR
failed = []

begin
  stacks = JSON.parse(stacks_json)
rescue JSON::ParserError => e
  abort "invalid stacks JSON: #{e.message}"
end

stacks.each do |stack|
  local_dir = File.join('compose-stacks', stack)
  live = File.join(base, stack)
  assignment_dir = File.join(local_dir, 'deployments', host_id)
  assignment = File.join(assignment_dir, '.env.template')

  if File.file?(assignment)
    stage = ComposeDeployment.staging_path(stack)
    cleanup = proc { ssh_command(remote, "rm -rf -- #{quote(stage)}") }
    begin
      merged = Tempfile.new(['merged-', '.env'])
      merge = ScriptCommands.capture_result('ruby', '.github/scripts/merge-dotenv.rb', File.join(local_dir, '.env.template'), assignment)
      unless merge[2].success?
        ScriptOutput.error('dotenv merge failed', context: "#{host_id}/#{stack}")
        failed << "#{host_id}/#{stack}"
        next
      end
      merged.write(merge[0])
      merged.close

      marker = ComposeDeployment.marker(stack)
      unless ssh_command(remote, "umask 077 && mkdir -p -- #{quote(base + '/.staging')} && mkdir -- #{quote(stage)}")
        ScriptOutput.error('unable to create remote staging directory', context: "#{host_id}/#{stack}"); failed << "#{host_id}/#{stack}"; next
      end
      unless system('rsync', '-r', '--delete', '--exclude=.env', '--exclude=.env.*', '--exclude=.git/', "#{local_dir}/", "#{remote}:#{stage}/")
        ScriptOutput.error('rsync failed', context: "#{host_id}/#{stack}"); failed << "#{host_id}/#{stack}"; next
      end
      unless ssh_command(remote, "cd #{quote(stage)} && if [ -f #{quote("deployments/#{host_id}/docker-compose.yaml")} ]; then cp -- #{quote("deployments/#{host_id}/docker-compose.yaml")} docker-compose.override.yaml && chmod 600 docker-compose.override.yaml; fi")
        ScriptOutput.error('unable to prepare host Compose override', context: "#{host_id}/#{stack}"); failed << "#{host_id}/#{stack}"; next
      end
      marker_path = File.join(stage, '.managed-by-github-actions')
      unless write_remote(remote, "umask 077 && cat > #{quote(marker_path)} && chmod 600 #{quote(marker_path)}", marker)
        ScriptOutput.error('unable to write deployment marker', context: "#{host_id}/#{stack}"); failed << "#{host_id}/#{stack}"; next
      end
      env_path = File.join(stage, '.env')
      env_tmp = File.join(stage, '.env.tmp')
      secret_command = "umask 077 && cat > #{quote(env_tmp)} && chmod 600 #{quote(env_tmp)} && mv -f -- #{quote(env_tmp)} #{quote(env_path)}"
      unless inject_to_remote(merged.path, remote, secret_command)
        ScriptOutput.error('secret injection failed; live stack was not changed', context: "#{host_id}/#{stack}"); failed << "#{host_id}/#{stack}"; next
      end
      unless ssh_command(remote, "cd #{quote(stage)} && docker compose --project-name #{quote(stack)} --env-file .env config --quiet")
        ScriptOutput.error('staged Compose validation failed', context: "#{host_id}/#{stack}"); failed << "#{host_id}/#{stack}"; next
      end
      marker_file = File.join(live, '.managed-by-github-actions')
      legacy_stale_traefik = "test #{quote(stack)} = traefik && test -d #{quote(File.join(live, 'traefik', 'traefik.yml'))} && test -d #{quote(File.join(live, 'traefik', 'dynamic'))}"
      marker_check = "if [ -e #{quote(live)} ]; then (test -f #{quote(marker_file)} && grep -Fxq 'STACK_NAME=#{stack}' #{quote(marker_file)}) || (#{legacy_stale_traefik}); fi"
      unless ssh_command(remote, marker_check)
        ScriptOutput.error('existing live directory is unmarked or has the wrong marker; refusing replacement', context: "#{host_id}/#{stack}"); failed << "#{host_id}/#{stack}"; next
      end
      retire = "cd #{quote(live)} && if [ -f docker-compose.yaml ]; then docker compose --project-name #{quote(stack)} --env-file .env down --remove-orphans; fi && if ! rm -rf -- #{quote(live)}; then docker run --rm --mount type=bind,source=#{quote(live)},target=/target busybox:1.36 sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +' && rm -rf -- #{quote(live)}; fi"
      unless ssh_command(remote, "if [ -e #{quote(live)} ]; then #{retire}; fi && mv -- #{quote(stage)} #{quote(live)}")
        ScriptOutput.error('publication failed', context: "#{host_id}/#{stack}"); failed << "#{host_id}/#{stack}"; next
      end
      up = "cd #{quote(live)} && if docker compose up --help 2>/dev/null | grep -q -- '--wait'; then docker compose --project-name #{quote(stack)} --env-file .env up -d --remove-orphans --pull always --wait --wait-timeout 120; else docker compose --project-name #{quote(stack)} --env-file .env up -d --remove-orphans --pull always; fi"
      unless ssh_command(remote, up)
        ScriptOutput.error('Compose up failed', context: "#{host_id}/#{stack}"); failed << "#{host_id}/#{stack}"; next
      end
      puts "[#{host_id}/#{stack}] deployed"
    ensure
      merged&.close!
      cleanup.call
    end
  else
    unless ssh_command(remote, "test -d #{quote(live)}")
      if ssh_command(remote, 'true')
        puts "[#{host_id}/#{stack}] not assigned and not deployed"
      else
        ScriptOutput.error('host connectivity failed; no cleanup attempted', context: "#{host_id}/#{stack}"); failed << "#{host_id}/#{stack}"
      end
      next
    end
    marker_file = File.join(live, '.managed-by-github-actions')
    unless ssh_command(remote, "test -f #{quote(marker_file)} && grep -Fxq 'STACK_NAME=#{stack}' #{quote(marker_file)}")
      ScriptOutput.error('unmarked live directory exists; refusing teardown', context: "#{host_id}/#{stack}"); failed << "#{host_id}/#{stack}"; next
    end
    retire = "cd #{quote(live)} && docker compose --project-name #{quote(stack)} --env-file .env down --remove-orphans && if ! rm -rf -- #{quote(live)}; then docker run --rm --mount type=bind,source=#{quote(live)},target=/target busybox:1.36 sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +' && rm -rf -- #{quote(live)}; fi"
    unless ssh_command(remote, retire)
      ScriptOutput.error('teardown failed; retaining remote directory', context: "#{host_id}/#{stack}"); failed << "#{host_id}/#{stack}"; next
    end
    puts "[#{host_id}/#{stack}] removed"
  end
end

unless failed.empty?
  ScriptOutput.error("Failed stack/host pairs: #{failed.join(' ')}")
  exit 1
end
