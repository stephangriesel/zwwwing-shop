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
    # Dockerfile for a Medusa.js Project

    # =================================================================
    # --- 1. Build Stage ---
    # Name this stage "build". We'll use it to install all dependencies
    # and create the production build artifacts.
    # =================================================================
    FROM node:20-slim AS build

    # Set the working directory
    WORKDIR /app

    # Copy package files.
    COPY package.json package-lock.json* ./
    RUN npm install --legacy-peer-deps

    # Copy the rest of the application source code
    COPY . .

    # Build the Medusa project for production. This creates the 'dist' folder
    # and compiles all .ts files into .js files inside 'dist'.
    RUN npm run build


    # =================================================================
    # --- 2. Production Stage ---
    # This is the final, lean image that will be deployed.
    # =================================================================
    FROM node:20-slim

    WORKDIR /app

    # Copy the built application and production dependencies from the "build" stage
    COPY --from=build /app/dist ./dist
    COPY --from=build /app/node_modules ./node_modules
    COPY --from=build /app/package.json ./package.json
    COPY --from=build /app/dist/medusa-config.js ./medusa-config.js

    # Expose the port Medusa runs on (default is 9000)
    EXPOSE 9000

    # The command to start the Medusa server in production mode
    CMD ["npm", "run", "start"]
    ```

2.  **Verify `medusa-config.ts`**: Ensure your configuration file uses environment variables for all sensitive data (database URL, Redis URL, JWT secret, etc.), as the Terraform module will provide these at runtime.

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
    docker tag my-medusa-backend:latest YOUR_AWS_ACCOUNT_ID.dkr.ecr.eu-central-1.amazonaws.com/my-medusa-backend:latest

    # 4. Push the image to ECR
    docker push YOUR_AWS_ACCOUNT_ID.dkr.ecr.eu-central-1.amazonaws.com/my-medusa-backend:latest
    ```
    *(Remember to replace `YOUR_AWS_ACCOUNT_ID` and other placeholders.)*

---

## Phase 4: Deploy the Infrastructure with Terraform

This phase covers the core infrastructure deployment using Terraform.

**Important Preamble:** The standard MedusaJS Terraform module can fail on AWS accounts with modern security settings (specifically, the `S3 Block Public Access` feature). The following instructions have been modified to work around this. We will download a local copy of the module, edit it to fix the permissions, and then use that local copy for the deployment.

1.  **Prepare the Local Module**
    First, set up the folder structure and download the module code.
    
    a. **Create Project Folders**: Create a new folder for your Terraform code (e.g., `medusa-infra`). Inside it, create a `modules` folder, and inside that, a `medusajs` folder.
    
    ```
    medusa-infra/
    └── modules/
        └── medusajs/
    ```
    
    b. **Download the Module**: Download the source code from the [module's GitHub repository](https://github.com/u11d-com/terraform-aws-medusajs). Unzip the file and copy all of its contents into your `medusa-infra/modules/medusajs/` directory.

2.  **Modify the Local Module Code**
    Next, apply two crucial fixes to the downloaded code.

    * **Fix S3 Permissions:** Replace the entire content of `modules/medusajs/modules/backend/s3.tf`. This corrects the S3 permissions to prevent `AccessDenied` errors.

        ```terraform
        # modules/medusajs/modules/backend/s3.tf
        
        # This bucket stores uploads from the MedusaJS backend
        resource "aws_s3_bucket" "uploads" {
          bucket = "${var.context.project}-${var.context.environment}-uploads"
          tags   = local.tags
        }
        
        # This policy allows public read access to the bucket objects
        resource "aws_s3_bucket_policy" "allow_public_read" {
          bucket = aws_s3_bucket.uploads.id
          policy = jsonencode({
            Version = "2012-10-17"
            Statement = [
              {
                Sid       = "PublicReadGetObject"
                Effect    = "Allow"
                Principal = "*"
                Action    = "s3:GetObject"
                Resource  = "${aws_s3_bucket.uploads.arn}/*"
              },
            ]
          })
          depends_on = [aws_s3_bucket_public_access_block.uploads]
        }
        
        # This block configures the public access settings for the bucket
        resource "aws_s3_bucket_public_access_block" "uploads" {
          bucket = aws_s3_bucket.uploads.id
        
          block_public_acls       = true
          block_public_policy     = false # MODIFIED: Allows public policy
          ignore_public_acls      = true
          restrict_public_buckets = false # MODIFIED: Allows public policy
        }
        ```

    * **Ensure Variables are Passed Correctly:** In `modules/medusajs/main.tf`, find the `module "backend"` block and ensure it passes the `context` variable down to the sub-module.

        ```terraform
        # In modules/medusajs/main.tf, find this block and ensure "context" is present
        
        module "backend" {
          # ... other existing arguments ...
          source                  = "./modules/backend"
          owner                   = var.owner
          backend_container_image = var.backend_container_image
        
          # Ensure this line exists to pass variables down
          context = var.context
        }
        ```

3.  **Create Your Root Terraform Files**
    Now, back in your main `medusa-infra` folder, create the following files.

    * **`main.tf`**: This file points to your local module and uses a `locals` block to pass variables neatly.
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
        
        # Create a local context object to pass to the module
        locals {
          context = {
            project     = var.project
            environment = var.environment
            owner       = var.owner
          }
        }
        
        # This is the module that builds the entire MedusaJS backend stack
        module "medusajs" {
          # Use the local, modified version of the module
          source = "./modules/medusajs"
        
          # Pass the context object and other required variables
          context                 = local.context
          owner                   = var.owner
          backend_container_image = var.backend_container_image
        }
        ```

    * **`variables.tf`**: This file declares all the input variables.
        ```terraform
        # variables.tf
        
        variable "project" {
          description = "The name of the project (e.g., mystore)."
          type        = string
        }
        
        variable "environment" {
          description = "The deployment environment (e.g., dev, staging, prod)."
          type        = string
        }
        
        variable "aws_region" {
          description = "The AWS region to deploy resources in."
          type        = string
        }
        
        variable "owner" {
          description = "The owner of the resources, for tagging purposes."
          type        = string
        }
        
        variable "backend_container_image" {
          description = "The full URI of the backend container image in ECR."
          type        = string
        }
        ```

    * **`terraform.tfvars`**: This file contains the actual values for your variables. This is the only file you should need to edit with your specific details.
        ```terraform
        # terraform.tfvars
        
        # The full image path from your ECR repository
        # e.g., "[123456789012.dkr.ecr.us-east-1.amazonaws.com/my-medusa-backend:latest](https://123456789012.dkr.ecr.us-east-1.amazonaws.com/my-medusa-backend:latest)"
        backend_container_image = "YOUR_ECR_IMAGE_URI"
        
        # You can change these to match your project
        project     = "medusa-commerce"
        environment = "dev"
        aws_region  = "us-east-1"
        owner       = "Your Name"
        ```

4.  **Deploy the Infrastructure**
    Run the following commands from your `medusa-infra` directory to initialize, plan, and apply your configuration.

    ```bash
    # 1. Initialize Terraform (downloads providers and links the local module)
    terraform init -reconfigure
    
    # 2. Preview the changes (highly recommended)
    terraform plan -out=medusa.tfplan
    
    # 3. Apply the changes to build the infrastructure in AWS
    #    This will take 15-20 minutes to provision everything.
    terraform apply "medusa.tfplan"
    ```

---

## Troubleshooting

#### Error on Update: `CannotUpdateEntityWhileInUse` (CloudFront)
* **Symptom**: When running `terraform apply` on an existing environment, you receive an error that the CloudFront origin cannot be updated because it's "in use".
* **Cause**: This is a limitation of the AWS CloudFront API. Terraform cannot modify certain core properties of a CloudFront origin while it is attached to a distribution.
* **Solution**: The solution is to force Terraform to recreate the CloudFront distribution by "tainting" it.

    **Warning:** This will cause several minutes of downtime for your API as the distribution is redeployed.

    1.  **Taint the CloudFront Distribution**
        Run the following command in your terminal:
        ```bash
        terraform taint "module.medusajs.module.backend[0].aws_cloudfront_distribution.main"
        ```
    2.  **Re-apply the Configuration**
        Run the apply command again. Terraform will now plan to destroy and recreate the tainted distribution, resolving the error.
        ```bash
        terraform apply
        ```

## Destroy the Infrastructure

When you no longer need the infrastructure, you can remove all AWS resources managed by this Terraform project with a single command.

```bash
# This will de-provision all resources.
terraform destroy
```

If it doesn't clean AWS resources completely then you need to do some manual cleaning:

## Manual AWS Cleanup

## Part 1: Manual Deletion Checklist

You must log into your AWS Console and manually delete every resource that is causing an error. This is a required manual reset. The order below is important to avoid dependency errors.

### 1. CloudFront (Origin Access and Distribution)
This is a two-step process. You must delete the Origin Access Controls first.

- **Step A: Delete Origin Access Controls**
  - Go to **Amazon CloudFront** -> **Origin access** (under the "Security" section).
  - Check both the **Origin access controls (OAC)** and **Origin access identities (OAI)** tabs.
  - Find any entry related to your project (e.g., `zwing-dev-backend-oac`), select it, and click **Delete**.

- **Step B: Delete the Distribution**
  - Go to **Amazon CloudFront** -> **Distributions**.
  - If any distribution related to your project exists, select it and click **Disable**. Wait several minutes for the status to update to `Disabled`.
  - Once disabled, select it again and click **Delete**. This can take over 10 minutes to complete.

### 2. ECS (Services and Cluster)
This is a two-step process. You must delete the services inside the cluster first.

- **Step A: Delete the ECS Services**
  - Go to **Amazon ECS** -> **Clusters** and click on the `zwing-dev-backend` cluster name.
  - Click the **Services** tab.
  - For each service listed (e.g., server, worker), select it and click **Delete**. Confirm by typing `delete`.
  - Wait until the list of services is empty.

- **Step B: Delete the ECS Cluster**
  - Once all services are gone, go back to the main **Clusters** page.
  - Select the `zwing-dev-backend` cluster and **Delete** it.

### 3. Load Balancer & Target Group
- Go to **EC2** -> **Load Balancers**. Delete `zwing-dev-backend-lb`.
- Go to **EC2** -> **Target Groups**. Delete `zwing-dev-backend-tg`.

### 4. RDS Database
- Go to **Amazon RDS** -> **Databases**.
- Find and delete the instance named `zwing-dev-rds`.
- **Important Tip:** If you can't delete it, click "Modify" and scroll down to disable the **"Deletion protection"** setting first, then try deleting again.

### 5. ElastiCache (Cluster and Subnet Group)
This is a two-step process. You must delete the cluster first.

- **Step A: Delete the Redis Cluster**
  - Go to **Amazon ElastiCache** -> **Redis clusters**.
  - Find the cluster associated with your project (e.g., `zwing-dev-redis`) and select it.
  - Click **Delete** and wait for the cluster to finish deleting completely.

- **Step B: Delete the Subnet Group**
  - Once the cluster is gone, go to **Amazon ElastiCache** -> **Subnet Groups**.
  - Find and **Delete** the subnet group named `zwing-dev-elasticache-db-subnet-group`.

### 6. S3 Bucket
- Go to **Amazon S3** -> **Buckets**.
- Find and delete the bucket named `zwing-dev-uploads`. You must empty it before you can delete it.

### 7. CloudWatch Log Group
- Go to **Amazon CloudWatch** -> **Log groups**.
- Find and delete the log group named `zwing-dev-backend/medusa-backend`.

### 8. IAM User
- Go to **IAM** -> **Users**.
- Find and delete the user named `zwing-dev-backend-s3-user`.


---

## Part 2: Final Verification (Before Re-applying)

After completing the manual deletion checklist, perform these two final checks to be 100% sure the environment is clean.

### A. Verify with AWS Tag Editor
- Go to **Resource Groups & Tag Editor** -> **Tag Editor**.
- Search for your project's tags in the correct region.
- The search result **must be empty**.

### B. Clean Local Terraform State
- In your project folder, delete the `terraform.tfstate`, `terraform.tfstate.backup`, and `.terraform` directory.

Once these steps are complete, please try the `terraform plan` and `terraform apply` one more time. This hidden "Origin Access" resource is the most likely cause of the repeated issue.

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