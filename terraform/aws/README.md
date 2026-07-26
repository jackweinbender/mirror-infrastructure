# terraform/aws

AWS resources for `labs.weinbender.io` static site hosting.

## Resources

| Resource | Purpose |
|----------|---------|
| `aws_route53_zone.labs` | Hosted zone for `labs.weinbender.io` |
| `aws_s3_bucket.labs` | Static site bucket (`labs-weinbender-io`) |
| `aws_s3_bucket_public_access_block.labs` | Block all public access |
| `aws_cloudfront_origin_access_control.labs` | OAC for CloudFront → S3 |
| `aws_acm_certificate.labs` | ACM cert for `labs.weinbender.io` (DNS validation) |
| `aws_cloudfront_distribution.labs` | CDN distribution (HTTPS, custom domain, compression) |
| `aws_route53_record.labs_*` | A/AAAA alias records → CloudFront |

## Backend

S3 backend in `backend.tf`:
```
bucket = "tf-backend-61rckk"
key    = "terraform-primary-325498355308.tfstate"
region = "us-east-1"
```

## Deploy

```bash
cd terraform/aws
terraform init
terraform plan
terraform apply
```

Requires AWS credentials with permissions for Route53, S3, CloudFront, ACM. CI uses `GithubActionsRole` (arn:aws:iam::325498355308:role/GithubActionsRole) via OIDC.

## Outputs

- `labs_nameservers` — NS records for delegation (if not using AWS as registrar)