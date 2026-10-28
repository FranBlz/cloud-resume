locals {
  crc_domain = aws_cloudfront_distribution.site_oac_distribution.domain_name
}

locals {
  counter_function_name = "${var.prefix}-visitor-counter"
}