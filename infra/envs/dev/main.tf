data "aws_caller_identity" "current" {}

locals {
  name = "${var.project}-dev"
  # images live in the persistent envs/shared stack; the registry URL is
  # deterministic, so no cross-stack state coupling is needed
  registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

# ---------------- network ----------------

module "network" {
  source = "../../modules/network"

  name = local.name
}

# ---------------- data ----------------

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

# ---------------- compute ----------------

resource "aws_ecs_cluster" "this" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

module "alb" {
  source = "../../modules/alb"

  name              = local.name
  vpc_id            = module.network.vpc_id
  vpc_cidr          = module.network.vpc_cidr
  public_subnet_ids = module.network.public_subnet_ids

  services = {
    menu = {
      port          = 8000
      health_path   = "/healthz"
      path_patterns = ["/stalls", "/stalls/*", "/docs", "/openapi.json"]
      priority      = 10
    }
    order = {
      port          = 8000
      health_path   = "/healthz"
      path_patterns = ["/orders", "/orders/*"]
      priority      = 20
    }
  }
}

# alarms (incl. the alb-target-5xx deploy gate), SNS email alerting, dashboard
module "observability" {
  source = "../../modules/observability"

  name           = local.name
  alert_email    = var.alert_email
  alb_arn_suffix = module.alb.alb_arn_suffix
  queue_name     = "${local.name}-order-events"
  dlq_name       = "${local.name}-order-events-dlq"
  cluster_name   = aws_ecs_cluster.this.name
  service_names = [
    "${local.name}-menu-service",
    "${local.name}-order-service",
    "${local.name}-notify-worker",
  ]
}

# ---------------- least-privilege task policies ----------------
# menu-service may touch ONLY the menus table; order-service only the orders
# table + publish to the queue; the worker only consumes from the queue.

data "aws_iam_policy_document" "menu_service" {
  statement {
    sid    = "MenusTable"
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
    resources = [module.menus_table.table_arn]
  }
}

data "aws_iam_policy_document" "order_service" {
  statement {
    sid    = "OrdersTable"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DescribeTable",
    ]
    resources = [module.orders_table.table_arn]
  }

  statement {
    sid    = "PublishOrderEvents"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [module.order_events.queue_arn]
  }
}

data "aws_iam_policy_document" "notify_worker" {
  statement {
    sid    = "ConsumeOrderEvents"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [module.order_events.queue_arn]
  }
}

# ---------------- services ----------------

module "menu_service" {
  source = "../../modules/ecs-service"

  name         = "${local.name}-menu-service"
  cluster_arn  = aws_ecs_cluster.this.arn
  cluster_name = aws_ecs_cluster.this.name
  image        = "${local.registry}/${var.project}/menu-service:${var.image_tag}"

  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  target_group_arn      = module.alb.target_group_arns["menu"]
  alb_security_group_id = module.alb.alb_security_group_id

  environment = {
    MENUS_TABLE = module.menus_table.table_name
    AWS_REGION  = var.aws_region
  }

  task_policy_json = data.aws_iam_policy_document.menu_service.json
}

module "order_service" {
  source = "../../modules/ecs-service"

  name         = "${local.name}-order-service"
  cluster_arn  = aws_ecs_cluster.this.arn
  cluster_name = aws_ecs_cluster.this.name
  image        = "${local.registry}/${var.project}/order-service:${var.image_tag}"

  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  target_group_arn      = module.alb.target_group_arns["order"]
  alb_security_group_id = module.alb.alb_security_group_id

  environment = {
    ORDERS_TABLE           = module.orders_table.table_name
    ORDER_EVENTS_QUEUE_URL = module.order_events.queue_url
    AWS_REGION             = var.aws_region
  }

  task_policy_json = data.aws_iam_policy_document.order_service.json
}

module "notify_worker" {
  source = "../../modules/ecs-service"

  name         = "${local.name}-notify-worker"
  cluster_arn  = aws_ecs_cluster.this.arn
  cluster_name = aws_ecs_cluster.this.name
  image        = "${local.registry}/${var.project}/notify-worker:${var.image_tag}"

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  # no target group: background worker, nothing routes to it

  environment = {
    ORDER_EVENTS_QUEUE_URL = module.order_events.queue_url
    WAIT_TIME_SECONDS      = "10"
    AWS_REGION             = var.aws_region
  }

  task_policy_json = data.aws_iam_policy_document.notify_worker.json
}
