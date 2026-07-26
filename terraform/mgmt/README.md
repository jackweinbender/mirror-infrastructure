# terraform/mgmt

Management / bootstrap resources — creates the Terraform state backend bucket.

## Resources

| Resource | Purpose |
|----------|---------|
| `random_string.storage_key` | Random suffix for bucket name uniqueness |
| `aws_s3_bucket.aws-backend-bucket` | S3 bucket `tf-backend-<random>` for all Terraform state |

## Usage

This is a **bootstrap** component — run first to create the backend bucket used by all other components.

```bash
cd terraform/mgmt
terraform init   # Uses local backend initially
terraform apply  # Creates tf-backend-<random> bucket
```

After apply, migrate other components to use this bucket (already configured in their `backend.tf` / `terraform.tf`).

## Note

Bucket name generated as `tf-backend-${random_string.storage_key.id}`. Current bucket: `tf-backend-61rckk` (shared across all components).