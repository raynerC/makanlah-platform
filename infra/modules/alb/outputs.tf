output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "For CloudWatch metric dimensions"
  value       = aws_lb.this.arn_suffix
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "target_group_arns" {
  description = "Map of service key -> target group ARN"
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn }
}
