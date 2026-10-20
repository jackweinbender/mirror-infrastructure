# frozen_string_literal: true

require 'yaml'

module StackInventory
  NAME_PATTERN = /\A[a-z0-9][a-z0-9_-]*\z/
  DEPLOYMENT_GROUP = 'deployment_hosts'

  module_function

  def deployment_host_ids(path)
    inventory = YAML.load_file(path, aliases: true) || {}
    hosts = group_hosts(inventory, DEPLOYMENT_GROUP)
    raise ArgumentError, "inventory has no hosts in #{DEPLOYMENT_GROUP}" if hosts.empty?

    ids = hosts.map { |hostname, _data| host_id(hostname) }
    invalid = ids.reject { |id| valid_id?(id) }
    raise ArgumentError, "invalid deployment host identifier: #{invalid.first}" unless invalid.empty?
    raise ArgumentError, 'deployment host identifiers are not unique' unless ids.uniq.length == ids.length

    ids.sort
  end

  def group_hosts(inventory, name)
    group = find_group(inventory.fetch('all', {}).fetch('children', {}), name)
    raise ArgumentError, "inventory has no #{name} group" unless group

    collect_hosts(group)
  end

  def find_group(groups, target)
    groups.each do |name, group|
      return group if name == target

      nested = find_group(group.fetch('children', {}) || {}, target)
      return nested if nested
    end
    nil
  end

  def collect_hosts(group)
    hosts = (group.fetch('hosts', {}) || {}).to_a
    (group.fetch('children', {}) || {}).each_value do |child|
      hosts.concat(collect_hosts(child))
    end
    hosts
  end

  def host_id(hostname)
    hostname.split('.').first
  end

  def valid_id?(id)
    NAME_PATTERN.match?(id)
  end
end
