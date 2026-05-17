################################################################################
# backend.tf — Remote State Infrastructure (Bootstrap)
#
# PURPOSE: Provisions the S3 bucket (versioning + SSE) and DynamoDB lock table
#          that Terraform uses as its remote backend.
#
# USAGE ORDER:
#   1. Run this file FIRST with a LOCAL backend to create S3 + DynamoDB.
#   2. Then uncomment the "backend s3" block in main.tf and run:
#        terraform init -reconfigure
#   3. Terraform will migrate local state to S3 automatically.
#
# NOTE: This file is intentionally separated from main.tf so it can be applied
#       independently during environment bootstrap.
################################################################################

################################################################################
# S3 BUCKET — Terraform State Store
################################################################################

resource "aws_s3_bucket" "tfstate" {
  bucket = "hubspoke-tfstate-${var.aws_region}"

  # Prevent accidental deletion of state bucket
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.tags, {
    Name    = "hubspoke-tfstate-${var.aws_region}"
    Purpose = "terraform-remote-state"
  })
}

# ─── Versioning — Required for state history and rollback ─────────────────────

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"   # ← versioning ON as requested
  }
}

# ─── Server-Side Encryption (AES-256) ────────────────────────────────────────

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
      # For KMS-managed encryption, replace above with:
      # sse_algorithm     = "aws:kms"
      # kms_master_key_id = aws_kms_key.tfstate.arn
    }
    bucket_key_enabled = true   # Reduces KMS API call costs
  }
}

# ─── Block ALL public access ──────────────────────────────────────────────────

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── Lifecycle policy — Expire non-current state versions after 90 days ───────

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  # Must wait for versioning to be configured first
  depends_on = [aws_s3_bucket_versioning.tfstate]

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {
      prefix = ""   # Apply to all objects in the bucket
    }

    noncurrent_version_expiration {
      noncurrent_days           = 90
      newer_noncurrent_versions = 5   # Keep the 5 most recent non-current versions
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ─── Bucket ownership controls ────────────────────────────────────────────────

resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    object_ownership = "BucketOwnerEnforced"   # Disables ACLs; owner has full control
  }
}

# ─── Bucket policy — Enforce TLS-only access ──────────────────────────────────

resource "aws_s3_bucket_policy" "tfstate_tls_only" {
  bucket = aws_s3_bucket.tfstate.id

  # Must wait for public access block to avoid conflict
  depends_on = [aws_s3_bucket_public_access_block.tfstate]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "DenyUnencryptedPut"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.tfstate.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "AES256"
          }
        }
      }
    ]
  })
}

################################################################################
# DYNAMODB TABLE — Terraform State Locking
# Prevents concurrent terraform operations from corrupting state.
################################################################################

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "hubspoke-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"   # No capacity planning; auto-scales
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Point-in-time recovery for audit / disaster recovery
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true   # Uses AWS-owned KMS key; set kms_key_arn for CMK
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.tags, {
    Name    = "hubspoke-tfstate-lock"
    Purpose = "terraform-state-locking"
  })
}

################################################################################
# OPTIONAL: KMS Key for state encryption (uncomment for higher compliance)
################################################################################

# resource "aws_kms_key" "tfstate" {
#   description             = "CMK for Terraform state encryption — hub-spoke"
#   deletion_window_in_days = 30
#   enable_key_rotation     = true
#
#   tags = merge(var.tags, {
#     Name    = "hubspoke-tfstate-cmk"
#     Purpose = "terraform-state-encryption"
#   })
# }
#
# resource "aws_kms_alias" "tfstate" {
#   name          = "alias/hubspoke-tfstate"
#   target_key_id = aws_kms_key.tfstate.key_id
# }
