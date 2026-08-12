#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'yaml'

inventory_path = ARGV.fetch(0)
inventory = YAML.load_file(inventory_path, aliases: true) || {}
workloads = inventory.fetch('workloads', {})
hosts = workloads.fetch('hosts', {})
name_pattern = /\A[a-z0-9][a-z0-9_-]*\z/

deploy_hosts = hosts.filter_map do |hostname, data|
  data ||= {}
  next unless Array(data['host_roles']).include?('deploy')

  id = hostname.split('.').first
  abort "discover deploy hosts: invalid or reserved deploy host identifier: #{id}" unless name_pattern.match?(id) && id != 'docker-host'

  { 'id' => id, 'address' => data['ansible_host'] || hostname }
end

abort 'discover deploy hosts: no workload hosts have the deploy role' if deploy_hosts.empty?
if deploy_hosts.map { |host| host['id'] }.uniq.length != deploy_hosts.length
  abort 'discover deploy hosts: deploy host identifiers are not unique'
end

selected_host = ENV.fetch('HOST_FILTER', '')
if !selected_host.empty?
  deploy_hosts.select! { |host| host['id'] == selected_host }
  abort "discover deploy hosts: selected host is not a deploy host: #{selected_host}" if deploy_hosts.empty?
end

deploy_hosts.sort_by! { |host| host['id'] }
puts JSON.generate(deploy_hosts)
