output "website_url" {
  description = "The URL of the website"
  value = var.enable_cloudfront ? (
    "https://${aws_cloudfront_distribution.s3_distribution[0].domain_name}"
  ) : (
    "http://${aws_s3_bucket_website_configuration.website[0].website_endpoint}"
  )
}

output "cloudfront_distribution_id" {
  description = "The ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.s3_distribution.id
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.website.bucket
}
