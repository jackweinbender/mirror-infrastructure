#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'shellwords'
require 'tempfile'

def ssh_command(remote, command)
  system('ssh', '-o', 'BatchMode=yes', remote, command)
end

def quote(value)
  Shellwords.escape(value)
end

def inject_to_remote(input, remote, command)
  Open3.pipeline([{'OP_SERVICE_ACCOUNT_TOKEN' => ENV['OP_SERVICE_ACCOUNT_TOKEN'].to_s}, 'op', 'inject', '-i', input], ['ssh', remote, command]).all?(&:success?)
end

def write_remote(remote, command, content)
  Open3.popen3('ssh', remote, command) do |stdin, _stdout, _stderr, wait_thread|
    stdin.write(content)
    stdin.close
    wait_thread.value.success?
  end
end

host_id, host_address, stacks_json = ARGV
abort 'usage: reconcile-host.rb HOST_ID HOST_ADDRESS STACKS_JSON' unless host_id && host_address && stacks_json

remote = "#{ENV.fetch('DOCKER_USER', 'deploy')}@#{host_address}"
base = '/etc/compose-stacks'
run_tag = "#{ENV['GITHUB_RUN_ID']}-#{ENV['GITHUB_RUN_ATTEMPT']}"
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
    stage = File.join(base, '.staging', "#{stack}-#{run_tag}")
    cleanup = proc { ssh_command(remote, "rm -rf -- #{quote(stage)}") }
    begin
      merged = Tempfile.new(['merged-', '.env'])
      merge = Open3.capture3('ruby', '.github/scripts/merge-dotenv.rb', File.join(local_dir, '.env.template'), assignment)
      unless merge[2].success?
        warn "::error::[#{host_id}/#{stack}] dotenv merge failed"
        failed << "#{host_id}/#{stack}"
        next
      end
      merged.write(merge[0])
      merged.close

      marker = "REPOSITORY=#{ENV['GITHUB_REPOSITORY']}\nSTACK_NAME=#{stack}\nCOMMIT_SHA=#{ENV['GITHUB_SHA']}\nWORKFLOW_RUN_ID=#{ENV['GITHUB_RUN_ID']}\nWORKFLOW_RUN_NUMBER=#{ENV['GITHUB_RUN_NUMBER']}\nSYNCED_AT=#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}\n"
      unless ssh_command(remote, "umask 077 && mkdir -p -- #{quote(base + '/.staging')} && mkdir -- #{quote(stage)}")
        warn "::error::[#{host_id}/#{stack}] unable to create remote staging directory"; failed << "#{host_id}/#{stack}"; next
      end
      unless system('rsync', '-r', '--delete', '--exclude=.env', '--exclude=.env.*', '--exclude=.git/', "#{local_dir}/", "#{remote}:#{stage}/")
        warn "::error::[#{host_id}/#{stack}] rsync failed"; failed << "#{host_id}/#{stack}"; next
      end
      unless ssh_command(remote, "cd #{quote(stage)} && if [ -f #{quote("deployments/#{host_id}/docker-compose.yaml")} ]; then cp -- #{quote("deployments/#{host_id}/docker-compose.yaml")} docker-compose.override.yaml && chmod 600 docker-compose.override.yaml; fi")
        warn "::error::[#{host_id}/#{stack}] unable to prepare host Compose override"; failed << "#{host_id}/#{stack}"; next
      end
      marker_path = File.join(stage, '.managed-by-github-actions')
      unless write_remote(remote, "umask 077 && cat > #{quote(marker_path)} && chmod 600 #{quote(marker_path)}", marker)
        warn "::error::[#{host_id}/#{stack}] unable to write deployment marker"; failed << "#{host_id}/#{stack}"; next
      end
      env_path = File.join(stage, '.env')
      env_tmp = File.join(stage, '.env.tmp')
      secret_command = "umask 077 && cat > #{quote(env_tmp)} && chmod 600 #{quote(env_tmp)} && mv -f -- #{quote(env_tmp)} #{quote(env_path)}"
      unless inject_to_remote(merged.path, remote, secret_command)
        warn "::error::[#{host_id}/#{stack}] secret injection failed; live stack was not changed"; failed << "#{host_id}/#{stack}"; next
      end
      unless ssh_command(remote, "cd #{quote(stage)} && docker compose --project-name #{quote(stack)} --env-file .env config --quiet")
        warn "::error::[#{host_id}/#{stack}] staged Compose validation failed"; failed << "#{host_id}/#{stack}"; next
      end
      marker_check = "if [ -e #{quote(live)} ]; then test -f #{quote(File.join(live, '.managed-by-github-actions'))} && grep -Fxq 'STACK_NAME=#{stack}' #{quote(File.join(live, '.managed-by-github-actions'))}; fi"
      unless ssh_command(remote, marker_check)
        warn "::error::[#{host_id}/#{stack}] existing live directory is unmarked or has the wrong marker; refusing replacement"; failed << "#{host_id}/#{stack}"; next
      end
      unless ssh_command(remote, "if [ -e #{quote(live)} ]; then rm -rf -- #{quote(live)}; fi && mv -- #{quote(stage)} #{quote(live)}")
        warn "::error::[#{host_id}/#{stack}] publication failed"; failed << "#{host_id}/#{stack}"; next
      end
      up = "cd #{quote(live)} && if docker compose up --help 2>/dev/null | grep -q -- '--wait'; then docker compose --project-name #{quote(stack)} --env-file .env up -d --remove-orphans --pull always --wait --wait-timeout 120; else docker compose --project-name #{quote(stack)} --env-file .env up -d --remove-orphans --pull always; fi"
      unless ssh_command(remote, up)
        warn "::error::[#{host_id}/#{stack}] Compose up failed"; failed << "#{host_id}/#{stack}"; next
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
        warn "::error::[#{host_id}/#{stack}] host connectivity failed; no cleanup attempted"; failed << "#{host_id}/#{stack}"
      end
      next
    end
    marker_file = File.join(live, '.managed-by-github-actions')
    unless ssh_command(remote, "test -f #{quote(marker_file)} && grep -Fxq 'STACK_NAME=#{stack}' #{quote(marker_file)}")
      warn "::error::[#{host_id}/#{stack}] unmarked live directory exists; refusing teardown"; failed << "#{host_id}/#{stack}"; next
    end
    unless ssh_command(remote, "cd #{quote(live)} && docker compose --project-name #{quote(stack)} --env-file .env down --remove-orphans")
      warn "::error::[#{host_id}/#{stack}] teardown failed; retaining remote directory"; failed << "#{host_id}/#{stack}"; next
    end
    unless ssh_command(remote, "rm -rf -- #{quote(live)}")
      warn "::error::[#{host_id}/#{stack}] teardown succeeded but directory removal failed"; failed << "#{host_id}/#{stack}"; next
    end
    puts "[#{host_id}/#{stack}] removed"
  end
end

unless failed.empty?
  warn "::error::Failed stack/host pairs: #{failed.join(' ')}"
  exit 1
end
