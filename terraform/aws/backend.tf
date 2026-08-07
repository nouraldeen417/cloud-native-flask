terraform {
  backend "s3" {
    bucket       = "tfstate-aws-152"
    key          = "flaskapp.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # native S3 locking — GA since Terraform 1.11, no DynamoDB needed
  }
}
