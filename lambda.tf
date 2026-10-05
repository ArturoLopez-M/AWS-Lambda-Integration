# Codigo de upload-lambda empaquetado en zip
data "archive_file" "upload" {
  type        = "zip"
  source_dir  = "${path.module}/src/upload"
  output_path = "${path.module}/upload-lambda.zip"
}

# Log group de upload-lambda
resource "aws_cloudwatch_log_group" "upload" {
  name              = "/aws/lambda/${local.name_prefix}-upload"
  retention_in_days = 14
}

# upload-lambda
resource "aws_lambda_function" "upload" {
  function_name    = "${local.name_prefix}-upload"
  role             = aws_iam_role.upload.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  memory_size      = 256
  timeout          = 30
  filename         = data.archive_file.upload.output_path
  source_code_hash = data.archive_file.upload.output_base64sha256

  environment {
    variables = {
      S3_BUCKET          = aws_s3_bucket.images_bucket.id
      UPLOAD_PREFIX      = local.uploads_prefix
      MAX_UPLOAD_BYTES   = "10485760"
      ALLOWED_EXTENSIONS = "jpg,jpeg,png,gif,webp"
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.upload_lambda.id]
  }

  # Las dependencias se instalan con npm antes del apply
  lifecycle {
    precondition {
      condition     = fileexists("${path.module}/src/upload/node_modules/busboy/package.json")
      error_message = "Faltan las dependencias. Ejecuta npm install dentro de src/upload."
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.upload,
    aws_iam_role_policy.upload,
    aws_iam_role_policy_attachment.upload_vpc,
    aws_vpc_endpoint.s3,
  ]
}