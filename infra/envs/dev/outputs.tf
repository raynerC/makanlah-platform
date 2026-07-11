output "alb_dns_name" {
  description = "Public entrypoint (HTTP)"
  value       = module.alb.alb_dns_name
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "order_events_queue_url" {
  value = module.order_events.queue_url
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}
