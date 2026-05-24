variable "aws_region" {
  description = "The AWS region to create resources in."
  type        = string
  default     = "us-east-1"
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name."
  type        = string
  default     = "my-static-website-"
}

variable "enable_cloudfront" {
  description = "If true, use CloudFront. If false, serve directly from S3."
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Domain name for static site"
  type        = string
}
