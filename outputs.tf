output "instance_ids" {
  description = "IDs of deployed EC2 instances"
  value       = module.ec2.instance_ids
}

output "environment" {
  description = "Current workspace"
  value       = terraform.workspace
}
