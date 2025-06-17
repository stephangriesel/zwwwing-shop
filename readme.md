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
- **Step A: Delete Origin Access Controls:** Go to **CloudFront** -> **Origin access** (under the "Security" section). Check both the **Origin access controls (OAC)** and **Origin access identities (OAI)** tabs. Delete any entries related to your project.
- **Step B: Delete the Distribution:** Go to **CloudFront** -> **Distributions**. **Disable** the distribution first, wait, then **Delete** it. This can take over 10 minutes to complete.

### 2. ECS (Services and Cluster)
- **Step A: Delete the ECS Services:** Go to **Amazon ECS** -> **Clusters** and click on your cluster name. Click the **Services** tab and **Delete** all services within it.
- **Step B: Delete the ECS Cluster:** Once services are gone, go back to the main **Clusters** page and **Delete** the cluster itself.

### 3. Load Balancer & Target Group
- Go to **EC2** -> **Load Balancers** and **Target Groups**. Delete any resources related to the project.

### 4. NAT Gateways and Elastic IPs
- **Step A: Delete NAT Gateways:** Go to **VPC** -> **NAT Gateways**. Find and delete any gateways related to the project. This must be done before releasing their IPs.
- **Step B: Release Elastic IPs:**
  - Go to **VPC** -> **Elastic IPs**.
  - For any leftover IP, check if it's still associated with a Network Interface. If so, copy the **`Network interface ID`**.
  - Go to **VPC** -> **Network Interfaces**. Find the interface by its ID, **Detach** it, then **Delete** it.
  - Go back to **Elastic IPs** and you can now **Release** the IP address.

### 5. RDS Database
- Go to **Amazon RDS** -> **Databases**. Find and delete the project's database instance.
- **Tip:** You may need to "Modify" the instance to disable **"Deletion protection"** first.

### 6. ElastiCache (Cluster and Subnet Group)
- **Step A: Delete the Redis Cluster:** Go to **ElastiCache** -> **Redis clusters**. Select and **Delete** the cluster.
- **Step B: Delete the Subnet Group:** Once the cluster is gone, go to **ElastiCache** -> **Subnet Groups** and **Delete** the group.

### 7. VPC and All its Contents
- Go to **VPC** -> **Your VPCs**. Select the project's VPC and click **Actions -> Delete VPC**. The wizard will help you remove remaining dependent resources like subnets, route tables, and internet gateways.

### 8. S3 Bucket
- Go to **Amazon S3** -> **Buckets**. Empty and then **Delete** the project's bucket.

### 9. CloudWatch Log Group
- Go to **Amazon CloudWatch** -> **Log groups**. Find and **Delete** the project's log group.

### 10. IAM User
- Go to **IAM** -> **Users**. Find and **Delete** the project's user.


---

## Part 2: Final Verification (Before Re-applying)

After completing the manual deletion checklist, perform these two final checks.

### A. Verify with AWS Tag Editor
- Go to **Resource Groups & Tag Editor** -> **Tag Editor**.
- Search for your project's tags in the correct region. The search result **must be empty**.

### B. Clean Local Terraform State
- In your project folder, delete the `terraform.tfstate`, `terraform.tfstate.backup`, and `.terraform` directory.

---

## Part 3: Post-Deployment Verification

After a `terraform apply` command completes successfully, follow these steps to verify that the backend is fully operational.

### 1. Retrieve the Backend API URL
First, to easily access the API endpoint, you need to expose the module's output.

- Create a new file named `outputs.tf` in your `medusa-infra` directory with the following content:
  ```hcl
  # outputs.tf

  output "backend_api_url" {
    description = "The public URL of the backend API load balancer."
    value       = module.medusajs.backend_api_url
  }
  ```
- Run `terraform apply` one more time. **This is a safe, quick operation that will only update the state file with the new output definition and will not change your infrastructure.**
- Once the apply is complete, run the following command to get your backend's public URL:
  ```bash
  terraform output backend_api_url
  ```

### 2. Perform a Live Health Check
- Use `curl` or your browser to access a standard endpoint on your new URL.
  ```bash
  # Replace YOUR_API_URL with the output from the previous step
  curl YOUR_API_URL/store/products
  ```
- A successful result is a JSON response with an empty list: `{"products":[],"count":0,"offset":0,"limit":100}`. This proves the server is running and connected to the database.

### 3. Create the First Admin User
This final test confirms database write access.
1. Go to **AWS Secrets Manager** in the AWS Console to get the new database credentials.
2. Temporarily update the `.env` file in your **local** MedusaJS project folder.
3. From your local project folder, run `npx medusa user -e your-email@example.com -p YourSuperSecretPassword`.
4. **CRITICAL:** Remove the production credentials from your local `.env` file immediately afterward.

Once the admin user is created, the backend is confirmed to be 100% operational.

---

## Part 4: Verify and Manage

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
