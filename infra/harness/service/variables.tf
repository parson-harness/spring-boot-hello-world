# variables.tf
variable "org_id" {
  type = string
}

variable "project_id" {
  type = string
}

variable "service_id" {
  type = string
}

variable "service_name" {
  type = string
}

variable "description" {
  type    = string
  default = "Registered via Terraform"
}

variable "docker_connector_ref" {
  type = string
}

variable "connector_ref" {
  type = string
}

variable "image_repo" {
  type = string
}

variable "image_name" {
  type = string
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "repo_name" {
  type = string
}
