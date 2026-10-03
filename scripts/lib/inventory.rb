# frozen_string_literal: true

require 'yaml'

module DeployInventory
  NAME_PATTERN = /\A[a-z0-9][a-z0-9_-]*\z/

  module_function

  def deploy_hosts(path)
    inventory = YAML.load_file(path, aliases: true) || {}
    hosts = inventory.fetch('workloads', {}).fetch('hosts', {})
    deploy_hosts = hosts.filter_map do |hostname, data|
      next unless Array(data&.fetch('host_roles', nil)).include?('deploy')

      id = hostname.split('.').first
      abort "discover deploy hosts: invalid or reserved deploy host identifier: #{id}" unless valid_id?(id) && id != 'docker-networking'

      { 'id' => id, 'address' => data['ansible_host'] || hostname }
    end

    abort 'discover deploy hosts: no workload hosts have the deploy role' if deploy_hosts.empty?
    abort 'discover deploy hosts: deploy host identifiers are not unique' unless deploy_hosts.map { |host| host['id'] }.uniq.length == deploy_hosts.length

    deploy_hosts.sort_by { |host| host['id'] }
  end

  def valid_id?(id)
    NAME_PATTERN.match?(id)
  end
end
