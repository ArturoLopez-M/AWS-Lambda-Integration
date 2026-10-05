locals {
  name_prefix      = "image-processor-${var.environment}"
  uploads_prefix   = "uploads/"
  processed_prefix = "processed/"
  crop_timeout     = 60
}