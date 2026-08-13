#!/usr/bin/env ruby

require "json"
require "yaml"

manifest = JSON.parse(File.read(".github/terraform-components.json"))
terraform_directories = Dir.children("terraform").select do |entry|
  !entry.start_with?(".") && File.directory?(File.join("terraform", entry))
end

workflow = YAML.load_file(".github/workflows/plan-or-apply.yml")
triggers = workflow["on"] || workflow[true]
dropdown = triggers.dig("workflow_dispatch", "inputs", "component", "options")

checks = {
  "Terraform directories missing from manifest" => terraform_directories - manifest,
  "Manifest entries missing Terraform directories" => manifest - terraform_directories,
  "Manual workflow choices missing from manifest" => dropdown - manifest,
  "Manifest entries missing from manual workflow choices" => manifest - dropdown
}

errors = checks.filter_map do |label, entries|
  "#{label}: #{entries.join(", ")}" unless entries.empty?
end

abort errors.join("\n") unless errors.empty?
puts "Terraform component manifest, directories, and workflow choices are consistent"
