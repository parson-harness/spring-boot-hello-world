output "delegate_role_arn" {
  description = "IAM Role ARN for the Harness delegate"
  value       = aws_iam_role.harness_delegate.arn
}

output "delegate_role_name" {
  description = "IAM Role name for the Harness delegate"
  value       = aws_iam_role.harness_delegate.name
}

output "instance_profile_name" {
  description = "EC2 Instance Profile name (if enabled)"
  value       = var.enable_ec2_assume ? aws_iam_instance_profile.harness_delegate[0].name : null
}

output "instance_profile_arn" {
  description = "EC2 Instance Profile ARN (if enabled)"
  value       = var.enable_ec2_assume ? aws_iam_instance_profile.harness_delegate[0].arn : null
}

output "enabled_permissions" {
  description = "List of enabled permission sets"
  value = {
    asg    = var.enable_asg_permissions
    lambda = var.enable_lambda_permissions
    eks    = var.enable_eks_permissions
    s3     = var.enable_s3_permissions
  }
}
