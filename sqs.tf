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