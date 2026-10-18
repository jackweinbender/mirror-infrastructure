# frozen_string_literal: true

module TerraformComponents
  module_function

  def changed(manifest, paths)
    shared_root_change = paths.any? do |path|
      path == 'terraform/components.json' ||
        path.match?(%r{\Aterraform/(?:[^/]+\.tf(?:\.json)?|[^/]+\.tfvars(?:\.json)?|\.terraform\.lock\.hcl)\z})
    end
    return manifest if shared_root_change

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
