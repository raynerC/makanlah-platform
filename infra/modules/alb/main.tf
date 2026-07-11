resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Internet-facing ALB"
  vpc_id      = var.vpc_id

  # public API entrypoint: internet ingress is the whole point; WAF rate-limits it
  #tfsec:ignore:aws-ec2-no-public-ingress-sgr
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "to targets in the VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.name}-alb" }
}

#tfsec:ignore:aws-elb-alb-not-public -- internet-facing by design: this is the public API entrypoint
resource "aws_lb" "this" {
  name                       = var.name
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = var.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  idle_timeout               = 60

  tags = { Name = var.name }
}

resource "aws_lb_target_group" "this" {
  for_each = var.services

  name        = "${var.name}-${each.key}"
  vpc_id      = var.vpc_id
  port        = each.value.port
  protocol    = "HTTP"
  target_type = "ip" # Fargate awsvpc tasks register by ENI IP

  deregistration_delay = 15

  health_check {
    path                = each.value.health_path
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = { Name = "${var.name}-${each.key}" }
}

# No custom domain yet, so no ACM cert: HTTP-only listener, documented trade-off.
# TLS termination on the ALB is a variable change away once a domain exists.
#tfsec:ignore:aws-elb-http-not-used
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"no such route\"}"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "this" {
  for_each = var.services

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  condition {
    path_pattern {
      values = each.value.path_patterns
    }
  }
}

# ---- WAF: rate-limit abusive clients at the edge ----

resource "aws_wafv2_web_acl" "this" {
  name  = var.name
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-known-bad-inputs"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }

  tags = { Name = var.name }
}

resource "aws_wafv2_web_acl_association" "this" {
  resource_arn = aws_lb.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
