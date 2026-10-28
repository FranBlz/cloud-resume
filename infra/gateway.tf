resource "aws_apigatewayv2_api" "crc_http_api" {
  name          = "${var.prefix}-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_methods = ["GET", "POST"]
    allow_origins = ["https://${local.crc_domain}"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_stage" "crc_stage_default" {
  api_id      = aws_apigatewayv2_api.crc_http_api.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = 1
    throttling_burst_limit = 5
  }
}

resource "aws_apigatewayv2_integration" "crc_lambda_integration" {
  api_id           = aws_apigatewayv2_api.crc_http_api.id
  integration_type = "AWS_PROXY"

  connection_type        = "INTERNET"
  description            = "CRC VCount Lambda proxy integration"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.vcount_lambda.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "crc_vcount_get_route" {
  api_id    = aws_apigatewayv2_api.crc_http_api.id
  route_key = "GET /visits"
  target    = "integrations/${aws_apigatewayv2_integration.crc_lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "crc_vcount_post_route" {
  api_id    = aws_apigatewayv2_api.crc_http_api.id
  route_key = "POST /visits"
  target    = "integrations/${aws_apigatewayv2_integration.crc_lambda_integration.id}"
}

resource "aws_lambda_permission" "crc_api_gw_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.vcount_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.crc_http_api.execution_arn}/*/*/visits"
}