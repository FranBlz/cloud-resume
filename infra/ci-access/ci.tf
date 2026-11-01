terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "tfstate-976550610911-us-east-1"
    key          = "ci-access/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "cloud-resume", ManagedBy = "terraform" }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "prefix" {
  description = "Prefix for the CI roles. Must NOT match site_prefix, or the apply role could edit itself."
  type        = string
  default     = "franb-ci-crc"
}

variable "site_prefix" {
  description = "Prefix the main infra/ root uses for everything it creates"
  type        = string
  default     = "franb-crc"
}

variable "github_repo" {
  description = "owner/name of the repository allowed to assume these roles"
  type        = string
  default     = "FranBlz/cloud-resume"
}

data "aws_caller_identity" "current" {}

# Read the outputs of infra/ (site_bucket_name, distribution_id, ...)
data "terraform_remote_state" "site" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "cloud-resume/terraform.tfstate"
    region = var.region
  }
}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "tfstate-${local.account_id}-${var.region}"
  site_state   = "arn:aws:s3:::${local.state_bucket}/cloud-resume/terraform.tfstate"

  site_bucket_arn  = "arn:aws:s3:::${data.terraform_remote_state.site.outputs.site_bucket_name}"
  distribution_arn = "arn:aws:cloudfront::${local.account_id}:distribution/${data.terraform_remote_state.site.outputs.distribution_id}"
}


# ---------- GitHub OIDC provider and trust policies ----------
resource "aws_iam_openid_connect_provider" "crc_github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]
}

data "aws_iam_policy_document" "oidc_plan_trust" {
  statement {
    sid    = "TrustPlanRole"
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.crc_github.arn]
    }

    actions = [
      "sts:AssumeRoleWithWebIdentity",
    ]

    condition {
      test     = "StringEquals"
      values   = ["sts.amazonaws.com"]
      variable = "token.actions.githubusercontent.com:aud"
    }

    condition {
      test     = "StringEquals"
      values   = ["repo:${var.github_repo}:pull_request"]
      variable = "token.actions.githubusercontent.com:sub"
    }
  }
}

data "aws_iam_policy_document" "oidc_apply_trust" {
  statement {
    sid    = "TrustApplyRole"
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.crc_github.arn]
    }

    actions = [
      "sts:AssumeRoleWithWebIdentity",
    ]

    condition {
      test     = "StringEquals"
      values   = ["sts.amazonaws.com"]
      variable = "token.actions.githubusercontent.com:aud"
    }

    condition {
      test     = "StringEquals"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
      variable = "token.actions.githubusercontent.com:sub"
    }
  }
}

data "aws_iam_policy_document" "oidc_deploy_trust" {
  statement {
    sid    = "TrustDeployRole"
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.crc_github.arn]
    }

    actions = [
      "sts:AssumeRoleWithWebIdentity",
    ]

    condition {
      test     = "StringEquals"
      values   = ["sts.amazonaws.com"]
      variable = "token.actions.githubusercontent.com:aud"
    }

    condition {
      test     = "StringEquals"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
      variable = "token.actions.githubusercontent.com:sub"
    }
  }
}


# ---------- Plan role (pull requests) ----------
resource "aws_iam_role" "crc_github_plan_role" {
  name               = "${var.prefix}-plan"
  assume_role_policy = data.aws_iam_policy_document.oidc_plan_trust.json
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.crc_github_plan_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_lock" {
  statement {
    sid       = "AllowStateLockFile"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.site_state}.tflock"]
  }
}

resource "aws_iam_role_policy" "plan_lock" {
  role   = aws_iam_role.crc_github_plan_role.name
  policy = data.aws_iam_policy_document.plan_lock.json
}


# ---------- Apply role (main) ----------
resource "aws_iam_role" "crc_github_apply_role" {
  name               = "${var.prefix}-apply"
  assume_role_policy = data.aws_iam_policy_document.oidc_apply_trust.json
}

data "aws_iam_policy_document" "apply_site" {
  statement {
    sid       = "AllowStateList"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.state_bucket}"]
  }

  statement {
    sid       = "AllowStateReadWrite"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.site_state, "${local.site_state}.tflock"]
  }

  statement {
    sid     = "AllowSiteBucketAll"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.site_prefix}-*",
      "arn:aws:s3:::${var.site_prefix}-*/*",
    ]
  }

  statement {
    sid       = "AllowDBAll"
    actions   = ["dynamodb:*"]
    resources = ["arn:aws:dynamodb:${var.region}:${local.account_id}:table/${var.site_prefix}-*"]
  }

  statement {
    sid       = "AllowLambdaAll"
    actions   = ["lambda:*"]
    resources = ["arn:aws:lambda:${var.region}:${local.account_id}:function:${var.site_prefix}-*"]
  }

  statement {
    sid     = "AllowGatewayAll"
    actions = ["apigateway:*"]
    resources = [
      "arn:aws:apigateway:${var.region}::/apis",
      "arn:aws:apigateway:${var.region}::/apis/*",
      "arn:aws:apigateway:${var.region}::/tags/*",
    ]
  }

  statement {
    sid     = "AllowLogsAll"
    actions = ["logs:*"]
    resources = [
      "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.site_prefix}-*",
      "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/apigateway/${var.site_prefix}-*",
    ]
  }

  statement {
    sid = "AllowLogsDescribeAndDelivery"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeResourcePolicies",
      "logs:PutResourcePolicy",
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "AllowSiteDistribution"
    actions = ["cloudfront:*"]
    resources = [
      local.distribution_arn,
      "arn:aws:cloudfront::${local.account_id}:origin-access-control/*",
    ]
  }

  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["cloudfront:Get*", "cloudfront:List*"]
    resources = ["*"]
  }

  statement {
    sid = "AllowSiteRoles"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/${var.site_prefix}-*"]
  }

  statement {
    sid = "AllowSiteRolePermissionsWithinBoundary"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:PutRolePermissionsBoundary",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/${var.site_prefix}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.site_boundary.arn]
    }
  }

  statement {
    sid       = "AllowPassSiteRolesToLambda"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${var.site_prefix}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }
}

# ---------- Permissions boundary for every role infra/ creates ----------
data "aws_iam_policy_document" "site_boundary" {
  statement {
    sid       = "AllowCounterTable"
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = ["arn:aws:dynamodb:${var.region}:${local.account_id}:table/${var.site_prefix}-*"]
  }

  statement {
    sid       = "AllowOwnLambdaLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.site_prefix}-*"]
  }
}

resource "aws_iam_policy" "site_boundary" {
  name        = "${var.site_prefix}-boundary"
  description = "Permissions boundary for roles managed by infra/ (cloud-resume)"
  policy      = data.aws_iam_policy_document.site_boundary.json
}

resource "aws_iam_role_policy" "apply_site" {
  role   = aws_iam_role.crc_github_apply_role.name
  policy = data.aws_iam_policy_document.apply_site.json
}


# ---------- Deploy role (main) ----------
resource "aws_iam_role" "crc_github_deploy_role" {
  name               = "${var.prefix}-deploy"
  assume_role_policy = data.aws_iam_policy_document.oidc_deploy_trust.json
}

data "aws_iam_policy_document" "deploy_site" {
  statement {
    sid       = "AllowSiteList"
    actions   = ["s3:ListBucket"]
    resources = [local.site_bucket_arn]
  }

  statement {
    sid       = "AllowSiteModify"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.site_bucket_arn}/*"]
  }

  statement {
    sid       = "AllowSiteInvalidate"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = [local.distribution_arn]
  }
}

resource "aws_iam_role_policy" "deploy_site" {
  role   = aws_iam_role.crc_github_deploy_role.name
  policy = data.aws_iam_policy_document.deploy_site.json
}


# ---------- Outputs ----------
output "site_boundary_arn" {
  value = aws_iam_policy.site_boundary.arn
}

output "plan_role_arn" {
  value = aws_iam_role.crc_github_plan_role.arn
}

output "apply_role_arn" {
  value = aws_iam_role.crc_github_apply_role.arn
}

output "deploy_role_arn" {
  value = aws_iam_role.crc_github_deploy_role.arn
}
