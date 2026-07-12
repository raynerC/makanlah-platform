output "alb_dns_name" {
  description = "Public entrypoint (HTTP)"
  value       = module.alb.alb_dns_name
}

output "order_events_queue_url" {
  value = module.order_events.queue_url
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "deployed_image_tag" {
  description = "Tag currently pinned in the task definitions — deploy.yml reads this for rollback"
  value       = var.image_tag
}
