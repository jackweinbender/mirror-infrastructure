#!/usr/bin/env ruby

require "json"

components = JSON.parse(
  File.read(File.expand_path("../terraform-components.json", __dir__))
)
paths = STDIN.read.split("\0").reject(&:empty?)
root_change = paths.any? { |path| path.split("/").length <= 2 }
changed = if root_change
  components
else
  paths.filter_map do |path|
    components.find { |component| path.start_with?("terraform/#{component}/") }
  end.uniq
end

puts "components=#{JSON.generate(changed)}"
puts "has_changes=#{!changed.empty?}"
