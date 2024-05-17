variable "environment" {
  description = "The environment to deploy the resources into"
  type        = string
}

variable "location" {
  description = "The Azure region to deploy the resources into"
  type        = string
  default     = "uksouth"
}

variable "vnet_resource_group_name" {
  description = "The name of the resource group containing the VNet"
  type        = string
  default     = "vnet-main"
}

variable "vnet_name" {
  description = "The name of the VNet to deploy the resources into"
  type        = string
  default     = "main"
}

variable "address_prefixes" {
  description = "The address prefixes to use for the subnet"
  type        = list(string)
  default     = ["172.28.4.0/25"]
}

variable "vmss_image_id" {
  description = "The ID of the image to use for the VMSS"
  type        = string
  default     = # "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/manual-github-runners/providers/Microsoft.Compute/galleries/mangitrun/images/runner/versions/latest"
}

variable "github_pat" {
  description = "The GitHub Personal Access Token to use for the runner"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.github_pat) >= 40
    error_message = "GitHub PAT must be at least 40 characters long"
  }
}

variable "github_org" {
  description = "The GitHub organisation to use for the runner"
  type        = string
  default     = "alztestappvia"
}

variable "github_runner_group" {
  description = "The GitHub runner group to use for the runner"
  type        = string
  default     = "Default"
}

variable "tags" {
  description = "The tags to apply to the resources"
  type        = map(string)
  default     = {}
}
