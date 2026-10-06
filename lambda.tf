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

# Codigo de crop-lambda empaquetado en zip
data "archive_file" "crop" {
  type        = "zip"
  source_dir  = "${path.module}/src/crop"
  output_path = "${path.module}/crop-lambda.zip"
}

# Log group de crop-lambda
resource "aws_cloudwatch_log_group" "crop" {
  name              = "/aws/lambda/${local.name_prefix}-crop"
  retention_in_days = 14
}

# crop-lambda
resource "aws_lambda_function" "crop" {
  function_name    = "${local.name_prefix}-crop"
  role             = aws_iam_role.crop.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  memory_size      = 512
  timeout          = local.crop_timeout
  filename         = data.archive_file.crop.output_path
  source_code_hash = data.archive_file.crop.output_base64sha256

  environment {
    variables = {
      UPLOAD_PREFIX    = local.uploads_prefix
      PROCESSED_PREFIX = local.processed_prefix
      THUMB_SIZE       = "40"
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.crop_lambda.id]
  }

  # sharp debe estar instalado para Linux antes del apply
  lifecycle {
    precondition {
      condition     = fileexists("${path.module}/src/crop/node_modules/@img/sharp-linux-x64/package.json")
      error_message = "Falta sharp para Linux. Dentro de src/crop ejecuta: npm install --omit=dev --os=linux --cpu=x64 --libc=glibc"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.crop,
    aws_iam_role_policy.crop,
    aws_iam_role_policy_attachment.crop_vpc,
    aws_vpc_endpoint.s3,
  ]
}

# La cola dispara crop-lambda sin necesitar un endpoint de SQS
resource "aws_lambda_event_source_mapping" "crop" {
  event_source_arn        = aws_sqs_queue.main.arn
  function_name           = aws_lambda_function.crop.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = 5
  }
}