#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'lib/terraform_components'

manifest = JSON.parse(File.read(File.expand_path('../terraform-components.json', __dir__)))
paths = STDIN.read.split("\0").reject(&:empty?)
changed = TerraformComponents.changed(manifest, paths)

puts "components=#{JSON.generate(changed)}"
puts "has_changes=#{!changed.empty?}"
