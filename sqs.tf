# Cola de mensajes fallidos
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name_prefix}-image-dlq"
  message_retention_seconds = 1209600 # 14 dias
  sqs_managed_sse_enabled   = true
}

# Cola principal
resource "aws_sqs_queue" "main" {
  name                       = "${local.name_prefix}-image-queue"
  visibility_timeout_seconds = local.crop_timeout * 6 # 360 s
  message_retention_seconds  = 86400                  # 1 dia
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

data "aws_caller_identity" "current" {}

# Permite que el bucket envie mensajes a la cola
resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PermitirS3"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.main.arn
      Condition = {
        ArnEquals    = { "aws:SourceArn" = aws_s3_bucket.images_bucket.arn }
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}