# need environment variables
# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY
provider "aws" {
  version = "~> 1.52"
  region  = "${var.aws_region}"
}

terraform {
  required_version = "> 0.11.10"

  # backend "s3" {
  #   bucket = "some-bucket"
  #   key    = "example/terraform.tfstate"
  #   region = "ap-northeast-1"
  # }
}
