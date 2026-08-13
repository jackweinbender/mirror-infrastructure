#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'lib/inventory'

inventory_path = ARGV.fetch(0)
puts JSON.generate(DeployInventory.deploy_hosts(inventory_path))
