locals {
  counter_function_name = "${var.prefix}-visitor-counter"
}

data "archive_file" "visitor_count_script" {
  type        = "zip"
  source_file = "${path.module}/../backend/visitor_counter.py"
  output_path = "${path.module}/build/visitor_counter.zip"
}

data "aws_iam_policy_document" "vcount_lambda_trust" {
  statement {
    sid    = "TrustLambdaRole"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
    ]
  }
}

resource "aws_iam_role" "vcount_lambda_role" {
  name               = "${var.prefix}-visitor-counter"
  assume_role_policy = data.aws_iam_policy_document.vcount_lambda_trust.json
}

data "aws_iam_policy_document" "vcount_lambda_permissions" {
  statement {
    sid    = "AllowedDynamoDBOperationsVCountLambda"
    effect = "Allow"

    actions = [
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
    ]

    resources = [aws_dynamodb_table.crc_stats.arn]
  }

  statement {
    sid    = "AllowedCloudwatchOperationsVCountLambda"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.vcount_lambda_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "vcount_lambda_permissions" {
  role   = aws_iam_role.vcount_lambda_role.id
  policy = data.aws_iam_policy_document.vcount_lambda_permissions.json
}

resource "aws_cloudwatch_log_group" "vcount_lambda_logs" {
  name              = "/aws/lambda/${local.counter_function_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "vcount_lambda" {
  function_name    = local.counter_function_name
  role             = aws_iam_role.vcount_lambda_role.arn
  runtime          = "python3.13"
  handler          = "visitor_counter.lambda_handler"
  filename         = data.archive_file.visitor_count_script.output_path
  source_code_hash = data.archive_file.visitor_count_script.output_base64sha256
  architectures    = ["arm64"]
  timeout          = 5

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.crc_stats.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.vcount_lambda_logs, aws_iam_role_policy.vcount_lambda_permissions]
}