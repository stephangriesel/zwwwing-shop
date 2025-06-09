# main.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# This is the module that builds the entire MedusaJS backend stack
module "medusajs" {
  source = "./modules/medusajs" # CHANGED: Points to your local copy now
  # version = "~> 1.0"          # REMOVED: Version is not used for local modules

  # --- Basic Configuration ---
  project     = var.project
  environment = var.environment
  owner       = var.owner
  # aws_region  = var.aws_region # REMOVED: This argument is not supported and is inherited from the provider above.

  # --- Application Image ---
  # The path to the Docker image you pushed to ECR
  backend_container_image = var.backend_container_image

  # --- S3 ARGUMENTS REMOVED ---
  # These arguments are removed because the fix is now handled inside the
  # module's own files (in s3.tf), and they are not valid here.
  # block_public_policy     = false
  # restrict_public_buckets = false
}