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

output "lambda_pipeline_id" {
  description = "Lambda pipeline identifier"
  value       = var.enable_lambda ? harness_platform_pipeline.lambda[0].identifier : null
}

output "k8s_pipeline_id" {
  description = "Kubernetes pipeline identifier"
  value       = var.enable_eks ? harness_platform_pipeline.k8s[0].identifier : null
}

output "next_steps" {
  description = "Next steps after provisioning"
  value       = <<-EOT
    
    Harness entities created! Next steps:
    
    1. Build artifacts:
       - Lambda: ./deploy-lambda.sh v1.0-blue (builds and pushes image)
       - K8s: ./deploy-eks.sh v1.0-blue (builds and pushes image)
    
    2. Run the pipeline in Harness:
       - Lambda: ${var.enable_lambda ? harness_platform_pipeline.lambda[0].identifier : "N/A"}
       - K8s: ${var.enable_eks ? harness_platform_pipeline.k8s[0].identifier : "N/A"}
    
    3. Select artifact version when prompted
    
  EOT
}
