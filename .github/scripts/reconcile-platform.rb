#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/commands'
require_relative 'lib/compose_deployment'
require_relative 'lib/output'

ssh_command = ScriptCommands.method(:ssh)

host_id, host_address = ARGV.fetch(0, nil), ARGV.fetch(1, nil)
ScriptOutput.usage!('usage: reconcile-platform.rb HOST_ID HOST_ADDRESS') unless host_id && host_address

remote_user = ENV.fetch('DOCKER_USER', 'deploy')
remote = "#{remote_user}@#{host_address}"
local_dir = ENV.fetch('LOCAL_DIR', 'compose-stacks/docker-networking')
base = ComposeDeployment::BASE_DIR
live = File.join(base, 'docker-networking')
stage = ComposeDeployment.staging_path('docker-networking')

cleanup = proc { ssh_command(remote, "rm -rf -- #{ScriptCommands.quote(stage)}") }
at_exit { cleanup.call }
error = proc { |message| ScriptOutput.fail!(message, prefix: "[#{host_id}/docker-networking]") }

error.call('unable to create remote staging directory') unless ssh_command(remote, "umask 077 && mkdir -p -- #{ScriptCommands.quote(base + '/.staging')} && mkdir -- #{ScriptCommands.quote(stage)}")
error.call('unable to prepare external proxy network') unless ssh_command(remote, 'docker network inspect proxy >/dev/null 2>&1 || docker network create --driver bridge --attachable proxy >/dev/null')

rsync_args = ['-r', '--delete', "--exclude-from=#{File.join(local_dir, '.rsyncexclude')}", '--exclude=.env', '--exclude=.env.*', '--exclude=.git/', "#{local_dir}/", "#{remote}:#{stage}/"]
error.call('rsync to staging failed') unless system('rsync', *rsync_args)
marker = ComposeDeployment.marker('docker-networking')
marker_command = "umask 077 && cat > #{ScriptCommands.quote(stage + '/.managed-by-github-actions')} && chmod 600 #{ScriptCommands.quote(stage + '/.managed-by-github-actions')}"
error.call('unable to write deployment marker') unless ScriptCommands.write_remote(remote, marker_command, marker)
error.call('unable to prepare platform environment') unless ssh_command(remote, "umask 077 && : > #{ScriptCommands.quote(stage + '/.env')} && chmod 600 #{ScriptCommands.quote(stage + '/.env')}")
error.call('staged Compose validation failed') unless ssh_command(remote, "cd -- #{ScriptCommands.quote(stage)} && docker compose --project-name docker-networking --env-file .env config --quiet")
marker_check = "if [ -e #{ScriptCommands.quote(live)} ]; then test -f #{ScriptCommands.quote(live + '/.managed-by-github-actions')} && grep -Fxq 'STACK_NAME=docker-networking' #{ScriptCommands.quote(live + '/.managed-by-github-actions')}; fi"
error.call('existing platform directory is unmarked or has the wrong marker; refusing replacement') unless ssh_command(remote, marker_check)
error.call('platform publication failed') unless ssh_command(remote, "if [ -e #{ScriptCommands.quote(live)} ]; then rm -rf -- #{ScriptCommands.quote(live)}; fi && mv -- #{ScriptCommands.quote(stage)} #{ScriptCommands.quote(live)}")
error.call('proxy network is unavailable after platform publication') unless ssh_command(remote, 'docker network inspect proxy >/dev/null 2>&1')
legacy = "#{base}/docker-host"
legacy_marker = File.join(legacy, '.managed-by-github-actions')
legacy_cleanup = "if [ -e #{ScriptCommands.quote(legacy)} ]; then test -f #{ScriptCommands.quote(legacy_marker)} && grep -Fxq 'STACK_NAME=docker-host' #{ScriptCommands.quote(legacy_marker)} && cd -- #{ScriptCommands.quote(legacy)} && docker compose --project-name docker-host --env-file .env down --remove-orphans && rm -rf -- #{ScriptCommands.quote(legacy)}; fi"
error.call('legacy docker-host migration failed') unless ssh_command(remote, legacy_cleanup)
error.call('unable to ensure external proxy network after legacy migration') unless ssh_command(remote, 'docker network inspect proxy >/dev/null 2>&1 || docker network create --driver bridge --attachable proxy >/dev/null')
puts "[#{host_id}/docker-networking] deployed"
