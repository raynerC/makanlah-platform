# EPHEMERAL demo stack — the Kubernetes track (spec Phase 5). Applied locally
# for a demo session (see scripts/demo-eks.sh), destroyed the same day.
# Not wired into CI: this stack's whole point is spin up -> evidence -> gone.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "makanlah-tfstate-022440376627"
    key          = "envs/eks-demo/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = "eks-demo"
      ManagedBy   = "terraform"
    }
  }
}

variable "project" {
  type    = string
  default = "makanlah"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

locals {
  name      = "${var.project}-eks"
  namespace = "makanlah"
}

# ---------------- network (subnet tags let the ALB controller discover them) ----------------

module "network" {
  source = "../../modules/network"

  name = local.name

  public_subnet_tags = {
    "kubernetes.io/role/elb"              = "1"
    "kubernetes.io/cluster/${local.name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"     = "1"
    "kubernetes.io/cluster/${local.name}" = "shared"
  }
}

# ---------------- cluster ----------------

module "eks" {
  source = "../../modules/eks"

  name               = local.name
  private_subnet_ids = module.network.private_subnet_ids
  public_subnet_ids  = module.network.public_subnet_ids
}

# ---------------- data (same modules as the ECS track) ----------------

module "menus_table" {
  source = "../../modules/dynamodb"

  name      = "${local.name}-menus"
  hash_key  = "pk"
  range_key = "sk"
}

module "orders_table" {
  source = "../../modules/dynamodb"

  name     = "${local.name}-orders"
  hash_key = "order_id"
}

module "order_events" {
  source = "../../modules/sqs"

  name = "${local.name}-order-events"
}

# ---------------- IRSA: pods -> IAM, no node-level credentials ----------------

# one role for the app namespace's service account (demo scope: the ECS track
# demonstrates per-service least privilege; here the story is IRSA itself)
data "aws_iam_policy_document" "app_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${local.namespace}:makanlah"]
    }
  }
}

data "aws_iam_policy_document" "app_permissions" {
  statement {
    sid    = "Tables"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchWriteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [module.menus_table.table_arn, module.orders_table.table_arn]
  }

  statement {
    sid    = "Queue"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [module.order_events.queue_arn]
  }
}

resource "aws_iam_role" "app" {
  name               = "${local.name}-app"
  assume_role_policy = data.aws_iam_policy_document.app_trust.json
}

resource "aws_iam_role_policy" "app" {
  name   = "app-permissions"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_permissions.json
}

# ALB controller: vendored upstream policy + IRSA trust to kube-system SA
data "aws_iam_policy_document" "alb_controller_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_issuer}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${local.name}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_trust.json
}

resource "aws_iam_role_policy" "alb_controller" {
  name   = "alb-controller"
  role   = aws_iam_role.alb_controller.id
  policy = file("${path.module}/../../../deploy/eks/alb-controller-iam-policy.json")
}

# ---------------- outputs ----------------

output "cluster_name" {
  value = module.eks.cluster_name
}

output "app_role_arn" {
  value = aws_iam_role.app.arn
}

output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller.arn
}

output "menus_table" {
  value = module.menus_table.table_name
}

output "orders_table" {
  value = module.orders_table.table_name
}

output "order_events_queue_url" {
  value = module.order_events.queue_url
}

output "vpc_id" {
  value = module.network.vpc_id
}
