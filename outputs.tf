output "api_url" {
  value = "${aws_apigatewayv2_api.http.api_endpoint}/upload"
}

output "bucket_name" {
  value = aws_s3_bucket.images_bucket.id
}

output "queue_url" {
  value = aws_sqs_queue.main.id
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.id
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}