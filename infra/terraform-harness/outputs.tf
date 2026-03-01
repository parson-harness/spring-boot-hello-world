output "project_id" {
  description = "Harness Project identifier"
  value       = local.project_id
}

output "aws_connector_id" {
  description = "AWS connector identifier"
  value       = harness_platform_connector_aws.aws.identifier
}

output "k8s_connector_id" {
  description = "Kubernetes connector identifier"
  value       = var.enable_eks ? harness_platform_connector_kubernetes.eks[0].identifier : null
}

output "environment_id" {
  description = "Environment identifier"
  value       = harness_platform_environment.env.identifier
}

output "asg_infrastructure_id" {
  description = "ASG infrastructure identifier"
  value       = var.enable_asg ? harness_platform_infrastructure.asg[0].identifier : null
}

output "lambda_infrastructure_id" {
  description = "Lambda infrastructure identifier"
  value       = var.enable_lambda ? harness_platform_infrastructure.lambda[0].identifier : null
}

output "k8s_infrastructure_id" {
  description = "Kubernetes infrastructure identifier"
  value       = var.enable_eks ? harness_platform_infrastructure.k8s[0].identifier : null
}

output "asg_service_id" {
  description = "ASG service identifier"
  value       = var.enable_asg ? harness_platform_service.asg[0].identifier : null
}

output "lambda_service_id" {
  description = "Lambda service identifier"
  value       = var.enable_lambda ? harness_platform_service.lambda[0].identifier : null
}

output "k8s_service_id" {
  description = "Kubernetes service identifier"
  value       = var.enable_eks ? harness_platform_service.k8s[0].identifier : null
}

output "next_steps" {
  description = "Next steps after provisioning"
  value       = <<-EOT
    
    Harness entities created! Next steps:
    
    1. Import pipelines from infra/harness/pipelines/:
       - asg-blue-green.yaml
       - lambda-canary.yaml
       - k8s-canary.yaml
    
    2. Update pipeline inputs with:
       - Service: ${var.enable_asg ? harness_platform_service.asg[0].identifier : "N/A"}
       - Environment: ${harness_platform_environment.env.identifier}
       - Infrastructure: See outputs above
    
    3. Build artifacts:
       - ASG: ./deploy-asg.sh (builds AMI)
       - Lambda: ./deploy-lambda.sh (builds image)
       - K8s: ./deploy-eks.sh (builds image)
    
    4. Run the pipeline!
    
  EOT
}
