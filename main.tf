# S3 bucket for static website hosting
resource "aws_s3_bucket" "website" {
  bucket_prefix = var.bucket_prefix
}

# Website configuration (only created if CloudFront is disabled)
resource "aws_s3_bucket_website_configuration" "website" {
  count  = var.enable_cloudfront ? 0 : 1
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }
}

# Make S3 bucket private
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id
  
  # If CloudFront is disabled, we must allow public policies to serve the site
  block_public_acls       = true
  block_public_policy     = var.enable_cloudfront
  ignore_public_acls      = true
  restrict_public_buckets = var.enable_cloudfront
}

# Origin Access Control for CloudFront (Recommended over OAI)
resource "aws_cloudfront_origin_access_control" "oac" {
  count                             = var.enable_cloudfront ? 1 : 0
  name                              = "oac-${var.bucket_prefix}"
  description                       = "OAC for static website"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  depends_on = [aws_s3_bucket_public_access_block.website]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      var.enable_cloudfront ? {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.s3_distribution[0].arn
          }
        }
      } : {
        # Direct S3 Public Read Policy
        Sid    = "PublicReadGetObject"
        Effect = "Allow"
        Principal = "*"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
      }
    ]
  })
}

# Upload website files to S3
resource "aws_s3_object" "website_files" {
  for_each = fileset("${path.module}/www", "**/*")

  bucket = aws_s3_bucket.website.id
  key    = each.value
  source = "${path.module}/www/${each.value}"
  etag   = filemd5("${path.module}/www/${each.value}")
  content_type = lookup({
    "html" = "text/html",
    "css"  = "text/css",
    "js"   = "application/javascript",
    "json" = "application/json",
    "png"  = "image/png",
    "jpg"  = "image/jpeg",
    "jpeg" = "image/jpeg",
    "gif"  = "image/gif",
    "svg"  = "image/svg+xml",
    "ico"  = "image/x-icon",
    "txt"  = "text/plain"
  }, split(".", each.value)[length(split(".", each.value)) - 1], "application/octet-stream")
}



# CloudFront Distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  # This count ensures the distribution is only created if enabled
  count = var.enable_cloudfront ? 1 : 0
  
  # Wait for the certificate to be fully validated before creating the distribution
  depends_on = [aws_acm_certificate_validation.cert]
  
  # Tell CloudFront to accept traffic for your custom domain
  aliases = [var.domain_name]

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.website.id}"
    
    # Using [0] because the OAC resource now also uses 'count'
    origin_access_control_id = aws_cloudfront_origin_access_control.oac[0].id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.website.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
 
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert[0].arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

}








# This fetches the Zone ID of your existing Route 53 domain automatically
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# Request the certificate using the aliased provider
resource "aws_acm_certificate" "cert" {
  count             = var.enable_cloudfront ? 1 : 0
  provider          = aws.us_east_1 # Explicitly tells Terraform to create this in us-east-1
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Create the validation record in your main Route 53 zone
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in (var.enable_cloudfront ? aws_acm_certificate.cert[0].domain_validation_options : []) : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# Wait for validation to complete before creating CloudFront
resource "aws_acm_certificate_validation" "cert" {
  count                   = var.enable_cloudfront ? 1 : 0
  provider                = aws.us_east_1 # Must match the certificate provider
  certificate_arn         = aws_acm_certificate.cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Record A: Points to CloudFront (HTTPS)
resource "aws_route53_record" "website_cf" {
  count   = var.enable_cloudfront ? 1 : 0
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution[0].domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# Record B: Points directly to S3 Website Endpoint (HTTP)
resource "aws_route53_record" "website_s3" {
  count   = var.enable_cloudfront ? 0 : 1
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_s3_bucket_website_configuration.website[0].website_domain
    zone_id                = aws_s3_bucket.website.hosted_zone_id
    evaluate_target_health = false
  }
}









