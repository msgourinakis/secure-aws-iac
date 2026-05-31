###########################
## PROVIDER  / S3 BUCKET ##
###########################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
}

####################
## BOOTSTRAP OIDC ##
####################

variable "github_username" {
  description = "GitHub username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "secure-aws-iac"
}