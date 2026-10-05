# Politica del endpoint: solo GetObject y PutObject sobre el bucket
resource "aws_vpc_endpoint_policy" "s3" {
  vpc_endpoint_id = aws_vpc_endpoint.s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AccesoSoloAlBucket"
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject", "s3:PutObject"]
      Resource  = "${aws_s3_bucket.images_bucket.arn}/*"
    }]
  })
}