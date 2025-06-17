# Deploy a Production-Ready MedusaJS Backend on AWS with Terraform

This guide provides a complete step-by-step plan to deploy a scalable and secure MedusaJS backend to Amazon Web Services (AWS). The entire infrastructure is managed using Terraform, ensuring an automated and repeatable process.

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [Phase 1: Prerequisites](#phase-1-prerequisites)
- [Phase 2: Dockerize Your Application](#phase-2-dockerize-your-application)
- [Phase 3: Push Image to AWS ECR](#phase-3-push-image-to-aws-ecr)
- [Phase 4: Deploy with Terraform](#phase-4-deploy-with-terraform)
- [Phase 5: Post-Deployment Verification](#phase-5-post-deployment-verification)
- [Phase 6: Infrastructure Management & Cleanup](#phase-6-infrastructure-management--cleanup)

---

## Architecture Overview

This plan will create the following architecture, managed entirely by **Terraform**:

* **Networking**: A dedicated VPC for security and isolation.
* **Database**: A managed PostgreSQL database using Amazon RDS.
* **Cache & Job Queue**: A managed Redis instance using Amazon ElastiCache.
* **Compute**: Your MedusaJS application (server and worker) running as containers on Amazon ECS with Fargate.
* **Container Registry**: An Amazon ECR repository to store your application's Docker image.
* **Secrets Management**: AWS Secrets Manager to securely store database credentials.
* **Logging**: Centralized logging with Amazon CloudWatch.

---

## Phase 1: Prerequisites

Before you write any Terraform code, ensure you have the following tools installed and configured on your computer:

* **An AWS Account**: Make sure you have an account with billing enabled and administrative access.
* **AWS CLI**: Install the AWS CLI and configure it with your credentials by running `aws configure`.
* **Terraform CLI**: Install [Terraform](https://www.terraform.io/downloads.html).
* **Docker Desktop**: Install [Docker](https://www.docker.com/products/docker-desktop).
* **A MedusaJS Project**: Have your MedusaJS application code ready on your local machine.

---

## Phase 2: Dockerize Your Application

Terraform will deploy the infrastructure, but it needs a packaged application to run. We'll use Docker for this.

1.  **Create a `Dockerfile`** in the root directory of your MedusaJS project.

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

    # Build the Medusa project for production. This creates the 'dist' folder.
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

2.  **Verify `medusa-config.ts`**: Ensure your configuration file uses environment variables for all sensitive data (database URL, Redis URL, etc.), as Terraform will provide these at runtime.

---

## Phase 3: Push Image to AWS ECR

Your Docker image needs to be stored in a registry that AWS can access, the **Amazon Elastic Container Registry (ECR)**.

1.  **Create an ECR Repository**:
    ```bash
    aws ecr create-repository --repository-name my-medusa-backend --region us-east-1
    ```
    *(Replace names and regions as needed.)*

2.  **Build, Tag, and Push the Image**:
    ```bash
    # 1. Authenticate Docker with ECR
    aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

    # 2. Build the image
    docker build -t my-medusa-backend .

    # 3. Tag the image for ECR
    docker tag my-medusa-backend:latest YOUR_AWS_ACCOUNT_[ID.dkr.ecr.us-east-1.amazonaws.com/my-medusa-backend:latest](https://ID.dkr.ecr.us-east-1.amazonaws.com/my-medusa-backend:latest)

    # 4. Push the image to ECR
    docker push YOUR_AWS_ACCOUNT_[ID.dkr.ecr.us-east-1.amazonaws.com/my-medusa-backend:latest](https://ID.dkr.ecr.us-east-1.amazonaws.com/my-medusa-backend:latest)
    ```
    *(Remember to replace `YOUR_AWS_ACCOUNT_ID` and other placeholders.)*

---

## Phase 4: Deploy with Terraform

This phase covers the core infrastructure deployment. These instructions use a local, modified copy of the standard Terraform module to work around common AWS security settings.

1.  **Prepare the Local Module**
    * Create the folder structure: `medusa-infra/modules/medusajs/`.
    * Download the module source code from its [GitHub repository](https://github.com/u11d-com/terraform-aws-medusajs) and place the contents into the `medusajs` folder you created.

2.  **Modify the Local Module Code**
    * **Fix S3 Permissions:** Replace the content of `modules/medusajs/modules/backend/s3.tf` with the following to allow public access:
        ```terraform
        # modules/medusajs/modules/backend/s3.tf
        
        resource "aws_s3_bucket" "uploads" {
          bucket = "${var.context.project}-${var.context.environment}-uploads"
          tags   = local.tags
        }
        
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
        
        resource "aws_s3_bucket_public_access_block" "uploads" {
          bucket = aws_s3_bucket.uploads.id
        
          block_public_acls       = true
          block_public_policy     = false # MODIFIED
          ignore_public_acls      = true
          restrict_public_buckets = false # MODIFIED
        }
        ```
    * **Ensure Variables are Passed:** In `modules/medusajs/main.tf`, find the `module "backend"` block and ensure the `context` variable is passed to the sub-module.
        ```terraform
        # In modules/medusajs/main.tf
        
        module "backend" {
          # ... other existing arguments ...
          context = var.context # Ensure this line exists
        }
        ```

3.  **Create Your Root Terraform Files**
    In your main `medusa-infra` folder, create `main.tf`, `variables.tf`, and `terraform.tfvars`.

    * **`main.tf`**:
        ```terraform
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
        
        locals {
          context = {
            project     = var.project
            environment = var.environment
            owner       = var.owner
          }
        }
        
        module "medusajs" {
          source                  = "./modules/medusajs"
          context                 = local.context
          owner                   = var.owner
          backend_container_image = var.backend_container_image
        }
        ```
    * **`variables.tf`**:
        ```terraform
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
    * **`terraform.tfvars`**:
        ```terraform
        # terraform.tfvars
        
        backend_container_image = "YOUR_ECR_IMAGE_URI"
        
        project     = "medusa-commerce"
        environment = "dev"
        aws_region  = "us-east-1"
        owner       = "Your Name"
        ```

4.  **Deploy the Infrastructure**
    ```bash
    # 1. Initialize Terraform
    terraform init -reconfigure
    
    # 2. Preview the changes (recommended)
    terraform plan -out=medusa.tfplan
    
    # 3. Apply the changes (will take 15-20 minutes)
    terraform apply "medusa.tfplan"
    ```

---

## Phase 5: Post-Deployment Verification

After a `terraform apply` command completes successfully, follow these steps to verify that the backend is fully operational.

### 1. Retrieve the Backend API URL
First, to easily access the API endpoint, create a new file named `outputs.tf` in your `medusa-infra` directory.

- **`outputs.tf`**:
  ```hcl
  output "backend_api_url" {
    description = "The public URL of the backend API load balancer."
    value       = module.medusajs.backend_api_url
  }

### 1. Update State and Get URL
Run `terraform apply` one more time. This is a safe, quick operation that will only update the state file with the new output definition and will not change your infrastructure.

Once complete, run the following command to get your URL:
```bash
terraform output backend_api_url
```

### 2. Perform a Live Health Check
Use curl or your browser to access a standard endpoint on your new URL.

```# Replace YOUR_API_URL with the output from the previous step
curl YOUR_API_URL/store/products
```
A successful result is a JSON response with an empty list:` {"products":[],"count":0,"offset":0,"limit":100}.`

3. Create the First Admin User
This final test confirms database write access.
1. Go to AWS Secrets Manager to get the new database credentials.
2. Temporarily update the `.env` file in your local MedusaJS project folder.
3. From your local project folder, run `npx medusa user -e your-email@example.com -p YourSuperSecretPassword.`
***CRITICAL:*** Remove the production credentials from your local `.env` file immediately afterward.  
Once the admin user is created, the backend is confirmed to be 100% operational.

## Phase 6: Infrastructure Management & Cleanup
Destroying All Resources
When you no longer need the infrastructure, you can remove all AWS resources managed by this project with a single command:

```terraform destroy```

***Troubleshooting Common Issues***
***CloudFront Update Error*** (`CannotUpdateEntityWhileInUse`)
If you get this error when updating an existing environment, you can force a recreation of the resource. Warning: This will cause several minutes of downtime.

1. Taint the resource:

```terraform taint "module.medusajs.module.backend[0].aws_cloudfront_distribution.main"```

2. Re-apply the configuration:

```terraform apply```

# Manual Cleanup Guide for Failed Destroys

If `terraform destroy` fails to remove everything, you must manually clean your AWS account. Follow this guide to avoid dependency errors.

---

### 1. CloudFront (Origin Access and Distribution)
* **Step A: Delete Origin Access Controls:** Go to **CloudFront** -> **Origin access**. Check both OAC and OAI tabs. Delete any entries related to your project.
* **Step B: Delete the Distribution:** Go to **CloudFront** -> **Distributions**. Disable the distribution first, wait, then **Delete** it.

---

### 2. ECS (Services and Cluster)
* **Step A: Delete the ECS Services:** Go to **Amazon ECS** -> **Clusters** and click on your cluster name. Click the **Services** tab and **Delete** all services within it.
* **Step B: Delete the ECS Cluster:** Once services are gone, go back to the main **Clusters** page and **Delete** the cluster itself.

---

### 3. Load Balancer & Target Group
* Go to **EC2** -> **Load Balancers** and **Target Groups**. Delete any resources related to the project.

---

### 4. NAT Gateways and Elastic IPs
* **Step A: Delete NAT Gateways:** Go to **VPC** -> **NAT Gateways**. Find and delete any gateways related to the project.
* **Step B: Release Elastic IPs:** Go to **VPC** -> **Elastic IPs**. You may need to first find the associated Network Interface, **Detach** it, then **Delete** it before you can release the IP.

---

### 5. RDS Database
* Go to **Amazon RDS** -> **Databases**. Find and delete the project's database instance. You may need to "Modify" it to disable "Deletion protection" first.

---

### 6. ElastiCache (Cluster and Subnet Group)
* **Step A: Delete the Redis Cluster:** Go to **ElastiCache** -> **Redis clusters**. Select and **Delete** the cluster.
* **Step B: Delete the Subnet Group:** Once the cluster is gone, go to **ElastiCache** -> **Subnet Groups** and **Delete** the group.

---

### 7. VPC and All its Contents
* Go to **VPC** -> **Your VPCs**. Select the project's VPC and click **Actions** -> **Delete VPC**.

---

### 8. S3 Bucket, CloudWatch Log Group, IAM User
* Delete these remaining resources from their respective consoles.
