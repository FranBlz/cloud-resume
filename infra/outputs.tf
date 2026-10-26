output "site_bucket_name" {
  description = "Name of the private S3 bucket that holds the site files (target for aws s3 sync)"
  value       = aws_s3_bucket.site_bucket.bucket
}

output "distribution_id" {
  description = "ID of the CloudFront distribution (needed for cache invalidations)"
  value       = aws_cloudfront_distribution.site_oac_distribution.id
}

output "site_url" {
  description = "Public HTTPS URL of the CV site"
  value       = "https://${aws_cloudfront_distribution.site_oac_distribution.domain_name}"
}
