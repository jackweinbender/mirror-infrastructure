#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'shellwords'

def ssh_command(remote, command)
  system('ssh', '-o', 'BatchMode=yes', remote, command)
end

def remote_quote(value)
  Shellwords.escape(value)
end

host_id, host_address = ARGV.fetch(0, nil), ARGV.fetch(1, nil)
abort 'usage: reconcile-platform.rb HOST_ID HOST_ADDRESS' unless host_id && host_address

remote_user = ENV.fetch('DOCKER_USER', 'deploy')
remote = "#{remote_user}@#{host_address}"
local_dir = ENV.fetch('LOCAL_DIR', 'compose-stacks/docker-host')
base = '/etc/compose-stacks'
live = "#{base}/docker-host"
run_tag = "#{ENV['GITHUB_RUN_ID']}-#{ENV['GITHUB_RUN_ATTEMPT']}"
stage = "#{base}/.staging/docker-host-#{run_tag}"

cleanup = proc { ssh_command(remote, "rm -rf -- #{remote_quote(stage)}") }
 at_exit { cleanup.call }
error = proc { |message| warn "::error::[#{host_id}/docker-host] #{message}"; exit 1 }

error.call('unable to create remote staging directory') unless ssh_command(remote, "umask 077 && mkdir -p -- #{remote_quote(base + '/.staging')} && mkdir -- #{remote_quote(stage)}")
error.call('unable to prepare external proxy network') unless ssh_command(remote, 'docker network inspect proxy >/dev/null 2>&1 || docker network create --driver bridge --attachable proxy >/dev/null')

rsync_args = ['-r', '--delete', "--exclude-from=#{File.join(local_dir, '.rsyncexclude')}", '--exclude=.env', '--exclude=.env.*', '--exclude=.git/', "#{local_dir}/", "#{remote}:#{stage}/"]
error.call('rsync to staging failed') unless system('rsync', *rsync_args)
error.call('unable to prepare host Compose override') unless ssh_command(remote, "cd -- #{remote_quote(stage)} && if [ -f #{remote_quote("docker-compose.#{host_id}.yaml")} ]; then cp -- #{remote_quote("docker-compose.#{host_id}.yaml")} docker-compose.override.yaml && chmod 600 docker-compose.override.yaml; fi")

marker = "REPOSITORY=#{ENV['GITHUB_REPOSITORY']}\nSTACK_NAME=docker-host\nCOMMIT_SHA=#{ENV['GITHUB_SHA']}\nWORKFLOW_RUN_ID=#{ENV['GITHUB_RUN_ID']}\nWORKFLOW_RUN_NUMBER=#{ENV['GITHUB_RUN_NUMBER']}\nSYNCED_AT=#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}\n"
marker_command = "umask 077 && cat > #{remote_quote(stage + '/.managed-by-github-actions')} && chmod 600 #{remote_quote(stage + '/.managed-by-github-actions')}"
error.call('unable to write deployment marker') unless IO.popen(['ssh', remote, marker_command], 'w') { |io| io.write(marker) }

secret_command = "umask 077 && cat > #{remote_quote(stage + '/.env.tmp')} && chmod 600 #{remote_quote(stage + '/.env.tmp')} && mv -f -- #{remote_quote(stage + '/.env.tmp')} #{remote_quote(stage + '/.env')}"
secret_ok = Open3.pipeline([{'OP_SERVICE_ACCOUNT_TOKEN' => ENV['OP_SERVICE_ACCOUNT_TOKEN'].to_s}, 'op', 'inject', '-i', File.join(local_dir, '.env.template')], ['ssh', remote, secret_command]).all?(&:success?)
error.call('secret injection failed; live platform was not changed') unless secret_ok
error.call('staged Compose validation failed') unless ssh_command(remote, "cd -- #{remote_quote(stage)} && docker compose --project-name docker-host --env-file .env config --quiet")
marker_check = "if [ -e #{remote_quote(live)} ]; then test -f #{remote_quote(live + '/.managed-by-github-actions')} && grep -Fxq 'STACK_NAME=docker-host' #{remote_quote(live + '/.managed-by-github-actions')}; fi"
error.call('existing platform directory is unmarked or has the wrong marker; refusing replacement') unless ssh_command(remote, marker_check)
error.call('platform publication failed') unless ssh_command(remote, "if [ -e #{remote_quote(live)} ]; then rm -rf -- #{remote_quote(live)}; fi && mv -- #{remote_quote(stage)} #{remote_quote(live)}")
up = "cd -- #{remote_quote(live)} && if docker compose up --help 2>/dev/null | grep -q -- '--wait'; then docker compose --project-name docker-host --env-file .env up -d --remove-orphans --pull always --wait --wait-timeout 120; else docker compose --project-name docker-host --env-file .env up -d --remove-orphans --pull always; fi"
error.call('Compose up failed') unless ssh_command(remote, up)
puts "[#{host_id}/docker-host] deployed"
