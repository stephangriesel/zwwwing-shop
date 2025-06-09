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
  block_public_policy     = false # This is our original S3 fix
  ignore_public_acls      = true
  restrict_public_buckets = false # This is our original S3 fix
}