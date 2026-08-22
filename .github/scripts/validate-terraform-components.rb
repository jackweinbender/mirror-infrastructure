#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative 'lib/output'
require_relative 'lib/terraform_components'

manifest = JSON.parse(File.read('.github/terraform-components.json'))
terraform_directories = Dir.children('terraform').select do |entry|
  !entry.start_with?('.') && File.directory?(File.join('terraform', entry))
end

workflow = YAML.load_file('.forgejo/workflows/plan-or-apply.yml')
triggers = workflow['on'] || workflow[true]
dropdown = triggers.dig('workflow_dispatch', 'inputs', 'component', 'options')

errors = TerraformComponents.consistency_checks(
  manifest: manifest,
  terraform_directories: terraform_directories,
  workflow_choices: dropdown
).filter_map do |label, entries|
  "#{label}: #{entries.join(', ')}" unless entries.empty?
end

ScriptOutput.fail!(errors.join("\n")) unless errors.empty?
puts 'Terraform component manifest, directories, and workflow choices are consistent'
