resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  tags = {
    Owner   = "stav"
    Project = "status-page-eks"
  }
}

# State files are the record of what exists in AWS. Versioning means a bad
# apply or a corrupted write can be rolled back to the previous version
# instead of being unrecoverable.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# State contains resource attributes in plaintext — including things like the
# RDS endpoint and, depending on the resource, generated passwords. Encrypt at
# rest. SSE-S3 (AES256) rather than KMS: no KMS permissions verified in this
# account, and this is enough for the threat model here.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Nothing about state should ever be publicly reachable.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
