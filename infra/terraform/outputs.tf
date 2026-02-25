output "s3_bucket_name" {
  description = "Name of the S3 bucket for artifacts"
  value       = aws_s3_bucket.artifacts.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.artifacts.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "upload_command" {
  description = "Command to upload the JAR file to S3"
  value       = "aws s3 cp target/spring-boot-hello-world-1.0-SNAPSHOT.jar s3://${aws_s3_bucket.artifacts.id}/"
}

output "prod_target_group_arn" {
  description = "ARN of the production target group"
  value       = aws_lb_target_group.prod.arn
}

output "stage_target_group_arn" {
  description = "ARN of the stage target group"
  value       = aws_lb_target_group.stage.arn
}

output "prod_listener_arn" {
  description = "ARN of the production listener"
  value       = aws_lb_listener.prod.arn
}

output "weighted_listener_rule_arn" {
  description = "ARN of the weighted listener rule for traffic shifting"
  value       = aws_lb_listener_rule.weighted.arn
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.app.id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "app_security_group_id" {
  description = "ID of the application security group"
  value       = aws_security_group.app.id
}
