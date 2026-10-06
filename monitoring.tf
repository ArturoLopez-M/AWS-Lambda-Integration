# Topico donde llegan las alarmas
resource "aws_sns_topic" "alarms" {
  name = "${local.name_prefix}-alarms"
}

# Alarma si hay mensajes en la cola de mensajes fallidos
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${local.name_prefix}-dlq-messages-alarm"
  alarm_description   = "Hay mensajes en la dlq"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}