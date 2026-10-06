# Politica que permite a lambda asumir los roles
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Rol de upload-lambda
resource "aws_iam_role" "upload" {
  name               = "upload-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Permisos de red para que la lambda funcione dentro de la VPC
resource "aws_iam_role_policy_attachment" "upload_vpc" {
  role       = aws_iam_role.upload.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Logs de su log group y PutObject solo en uploads/
resource "aws_iam_role_policy" "upload" {
  name = "upload-lambda-policy"
  role = aws_iam_role.upload.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.upload.arn}:*"
      },
      {
        Sid      = "PutObjectEnUploads"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.images_bucket.arn}/${local.uploads_prefix}*"
      }
    ]
  })
}

# Rol de crop-lambda
resource "aws_iam_role" "crop" {
  name               = "crop-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Permisos de red para que la lambda funcione dentro de la VPC
resource "aws_iam_role_policy_attachment" "crop_vpc" {
  role       = aws_iam_role.crop.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Logs, lectura en uploads/, escritura en processed/ y consumo de la cola
resource "aws_iam_role_policy" "crop" {
  name = "crop-lambda-policy"
  role = aws_iam_role.crop.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.crop.arn}:*"
      },
      {
        Sid      = "GetObjectEnUploads"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.images_bucket.arn}/${local.uploads_prefix}*"
      },
      {
        Sid      = "PutObjectEnProcessed"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.images_bucket.arn}/${local.processed_prefix}*"
      },
      {
        Sid    = "ConsumirCola"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.main.arn
      }
    ]
  })
}