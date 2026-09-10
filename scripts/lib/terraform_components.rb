# frozen_string_literal: true

module TerraformComponents
  module_function

  def changed(manifest, paths)
    return manifest if paths.any? { |path| path.split('/').length <= 2 }

    paths.filter_map do |path|
      manifest.find { |component| path.start_with?("terraform/#{component}/") }
    end.uniq
  end

  def consistency_checks(manifest:, terraform_directories:)
    {
      'Terraform directories missing from manifest' => terraform_directories - manifest,
      'Manifest entries missing Terraform directories' => manifest - terraform_directories
    }
  end
end
