resource "random_id" "s3_bucket_id" {
  byte_length = 8
}

resource "aws_s3_bucket" "csye6225_bucket" {
  bucket = "csye6225-${random_id.s3_bucket_id.hex}"

  # Allow bucket deletion even if it is not empty
  force_destroy = true

  tags = {
    Name = "csye6225-attachments-bucket"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "csye6225_bucket_config" {
  bucket = aws_s3_bucket.csye6225_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle policy to transition objects to STANDARD_IA after 30 days
resource "aws_s3_bucket_lifecycle_configuration" "csye6225_bucket_lifecycle" {
  bucket = aws_s3_bucket.csye6225_bucket.id

  rule {
    id     = "transition-rule"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}
