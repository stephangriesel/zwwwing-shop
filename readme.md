# Deploy a Production-Ready MedusaJS Backend on AWS with Terraform

This guide provides a complete step-by-step plan to deploy a scalable and secure MedusaJS backend to Amazon Web Services (AWS). The entire infrastructure is managed using Terraform, ensuring an automated and repeatable process.

## Table of Contents
- [The Goal: Architecture Overview](#the-goal-architecture-overview)
- [Phase 1: Prerequisites (Your Local Setup)](#phase-1-prerequisites-your-local-setup)
- [Phase 2: Dockerize Your MedusaJS Application](#phase-2-dockerize-your-medusajs-application)
- [Phase 3: Build and Push the Docker Image to AWS ECR](#phase-3-build-and-push-the-docker-image-to-aws-ecr)
- [Phase 4: Deploy the Infrastructure with Terraform](#phase-4-deploy-the-infrastructure-with-terraform)
- [Phase 5: Verify and Manage](#phase-5-verify-and-manage)

---

## The Goal: Architecture Overview

This plan will create the following architecture, managed entirely by **Terraform**:

* **Networking**: A dedicated VPC for security and isolation.
* **Database**: A managed PostgreSQL database using Amazon RDS.
* **Cache & Job Queue**: A managed Redis instance using Amazon ElastiCache.
* **Compute**: Your MedusaJS application (server and worker) running as containers on Amazon ECS with Fargate.
* **Container Registry**: An Amazon ECR repository to store your application's Docker image.
* **Secrets Management**: AWS Secrets Manager to securely store database credentials.
* **Logging**: Centralized logging with Amazon CloudWatch.

---

## Phase 1: Prerequisites (Your Local Setup)

Before you write any Terraform code, ensure you have the following tools installed and configured on your computer:

* **An AWS Account**: Make sure you have an account with billing enabled and administrative access.
* **AWS CLI**: Install the AWS CLI and configure it with your credentials by running `aws configure`. This allows Terraform to authenticate with your AWS account.
* **Terraform CLI**: Install [Terraform](https://www.terraform.io/downloads.html).
* **Docker Desktop**: Install [Docker](https://www.docker.com/products/docker-desktop). We need this to package your MedusaJS app into a container.
* **A MedusaJS Project**: Have your MedusaJS application code ready on your local machine.

---

## Phase 2: Dockerize Your MedusaJS Application

Terraform will deploy the infrastructure, but it needs a packaged application to run on that infrastructure. We'll use Docker for this.

1.  **Create a `Dockerfile`** in the root directory of your MedusaJS project. This file contains instructions to build a production-optimized image of your application.

    ```dockerfile
    # --- 1. Build Stage ---
    # Use a Node.js base image
    FROM node:18-slim AS build

    # Set the working directory
    WORKDIR /app

    # Install build dependencies
    RUN apt-get update && apt-get install -y --no-install-recommends build-essential python3

    # Copy package files and install dependencies
    COPY package.json package-lock.json* ./
    RUN npm install

    # Copy the rest of the application source code
    COPY . .

    # Build the Medusa project for production
    RUN npm run build

    # --- 2. Production Stage ---
    # Use a smaller, more secure base image for the final product
    FROM node:18-slim AS production

    WORKDIR /app

    # Copy only the necessary files from the build stage
    COPY --from=build /app/node_modules ./node_modules
    COPY --from=build /app/package.json ./package.json
    COPY --from=build /app/dist ./dist
    COPY --from=build /app/medusa-config.js ./medusa-config.js

    # Expose the port Medusa runs on
    EXPOSE 9000

    # The command to run the Medusa server
    CMD ["npm", "run", "start"]
    ```

2.  **Verify `medusa-config.js`**: Ensure your configuration file uses environment variables for all sensitive data (database URL, Redis URL, JWT secret, etc.), as the Terraform module will provide these at runtime.

---

## Phase 3: Build and Push the Docker Image to AWS ECR

Your Docker image needs to be stored in a registry that AWS can access. We'll use the **Amazon Elastic Container Registry (ECR)**.

1.  **Create an ECR Repository**: Use the AWS CLI to create a private repository.

    ```bash
    aws ecr create-repository --repository-name my-medusa-backend --region us-east-1
    ```
    *(Replace `my-medusa-backend` with your desired name and `us-east-1` with your preferred AWS region.)*

2.  **Build, Tag, and Push the Image**: Execute these commands in your terminal from your project's root directory.

    ```bash
    # 1. Authenticate Docker with your ECR registry
    aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

    # 2. Build the Docker image
    docker build -t my-medusa-backend .

    # 3. Tag the image for ECR
    docker tag my-medusa-backend:latest YOUR_AWS_ACCOUNT_[ID.dkr.ecr.us-east-1.amazonaws.com/my-medusa-backend:latest](https://ID.dkr.ecr.us-east-1.amazonaws.com/my-medusa-backend:latest)

    # 4. Push the image to ECR
    docker push YOUR_AWS_ACCOUNT_[ID.dkr.ecr.us-east-1.amazonaws.com/my-medusa-backend:latest](https://ID.dkr.ecr.us-east-1.amazonaws.com/my-medusa-backend:latest)
    ```
    *(Remember to replace `YOUR_AWS_ACCOUNT_ID` and other placeholders.)*

---

## Phase 4: Deploy the Infrastructure with Terraform

Now for the core part. We will create a few files to define our infrastructure.

Create a new, separate folder for your Terraform code (e.g., `medusa-infra`). Inside it, create the following files:

* **`main.tf`**: This file defines the infrastructure by calling the pre-built MedusaJS module.

    ```terraform
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
      source  = "u11d-com/medusajs/aws"
      version = "~> 1.0" # Use a specific version for production stability

      # --- Basic Configuration ---
      project     = var.project
      environment = var.environment
      aws_region  = var.aws_region

      # --- Application Image ---
      # The path to the Docker image you pushed to ECR
      backend_container_image = var.backend_container_image
    }
    ```

* **`variables.tf`**: This file declares the variables used in `main.tf`.

    ```terraform
    # variables.tf

    variable "project" {
      description = "The name of the project."
      type        = string
      default     = "mystore"
    }

    variable "environment" {
      description = "The deployment environment (e.g., staging, production)."
      type        = string
      default     = "staging"
    }

    variable "aws_region" {
      description = "The AWS region to deploy resources in."
      type        = string
      default     = "us-east-1"
    }

    variable "backend_container_image" {
      description = "The full URI of the backend container image in ECR."
      type        = string
    }
    ```

* **`terraform.tfvars`**: This file contains the actual values for your variables. **This is the only file you should need to edit with your specific details.**

    ```terraform
    # terraform.tfvars

    # The full image path from Step 3.
    # e.g., "[123456789012.dkr.ecr.us-east-1.amazonaws.com/my-medusa-backend:latest](https://123456789012.dkr.ecr.us-east-1.amazonaws.com/my-medusa-backend:latest)"
    backend_container_image = "YOUR_ECR_IMAGE_URI"

    # You can change these if you like
    project     = "medusa-commerce"
    environment = "dev"
    aws_region  = "us-east-1"
    ```

**Deploy!** Now, run the following commands from your `medusa-infra` directory:

```bash
# 1. Initialize Terraform (downloads the provider and module)
terraform init

# 2. Preview the changes (highly recommended)
terraform plan

# 3. Apply the changes to build the infrastructure in AWS
#    This will take 15-20 minutes to provision everything.
terraform apply
```

---

## Phase 5: Verify and Manage

* **Get Outputs**: Once `terraform apply` is complete, it will display outputs, including the API endpoint URL. You can also retrieve them anytime with:
    ```bash
    terraform output backend_api_url
    ```

* **Test the API**: Use a tool like `curl` or Postman to make a request to the `/store/products` endpoint of your new API URL. You should get an empty array `[]` because the database is new and has no data.

* **Seed the Database**: Your new database is empty. You'll need to create an admin user. The simplest way is to temporarily update your local `.env` file to point to your new RDS database (get the credentials from the AWS Secrets Manager console) and run:
    ```bash
    # Run from your local Medusa project directory
    medusa user -e some-email@example.com -p some-super-secret-password
    ```

* **Tear Down**: When you are done experimenting, you can destroy all the resources to avoid incurring further costs with a single command:
    ```bash
    terraform destroy
    ```