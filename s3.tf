# Sufijo para que el nombre del bucket sea unico
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Bloqueo de acceso publico
resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Cifrado AES-256
resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket     = aws_s3_bucket.images_bucket.id
  depends_on = [aws_s3_bucket_public_access_block.images]

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning activado
resource "aws_s3_bucket_versioning" "images" {
  bucket     = aws_s3_bucket.images_bucket.id
  depends_on = [aws_s3_bucket_server_side_encryption_configuration.images]

  versioning_configuration {
    status = "Enabled"
  }
}