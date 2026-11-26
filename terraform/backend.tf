# Remote state: shared by your laptop and the GitHub Actions workflow.
# The bucket is created by ../bootstrap (state.tf). See backend.tf.example for
# why: versioned, encrypted, private, with S3 native locking (no DynamoDB).

terraform {
  backend "s3" {
    bucket       = "tfbrownbag-tfstate-mblumberg"
    key          = "tf-brownbag/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
