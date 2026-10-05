# Security group de upload-lambda
resource "aws_security_group" "upload_lambda" {
  name        = "upload-lambda-sg-${var.environment}"
  description = "upload-lambda: sin entrada, salida 443 solo a S3"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "sg-upload-lambda-${var.environment}"
  }
}

# Security group de crop-lambda
resource "aws_security_group" "crop_lambda" {
  name        = "crop-lambda-sg-${var.environment}"
  description = "crop-lambda: sin entrada, salida 443 solo a S3"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "sg-crop-lambda-${var.environment}"
  }
}

# Salida de upload-lambda hacia S3 (endpoint gateway, por prefix list)
resource "aws_vpc_security_group_egress_rule" "upload_to_s3" {
  security_group_id = aws_security_group.upload_lambda.id
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# Salida de crop-lambda hacia S3 (endpoint gateway, por prefix list)
resource "aws_vpc_security_group_egress_rule" "crop_to_s3" {
  security_group_id = aws_security_group.crop_lambda.id
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}