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

  # Hosts eligible for application assignments. Only deploy hosts are returned
  # by deploy_hosts and can ever become GitHub Actions deployment targets.
  def application_host_ids(path)
    inventory = YAML.load_file(path, aliases: true) || {}
    hosts = inventory.fetch('workloads', {}).fetch('hosts', {})
    application_hosts = hosts.filter_map do |hostname, data|
      roles = Array(data&.fetch('host_roles', nil))
      next unless roles.include?('deploy') || roles.include?('c5e_reconciler')

      id = hostname.split('.').first
      unless valid_id?(id) && id != 'docker-networking'
        raise ArgumentError, "invalid or reserved application host identifier: #{id}"
      end

      id
    end

    if application_hosts.uniq.length != application_hosts.length
      raise ArgumentError, 'application host identifiers are not unique'
    end

    application_hosts.sort
  end

  def valid_id?(id)
    NAME_PATTERN.match?(id)
  end
end
