# id of AWS account that owns the public AMI's

variable "csoc_account_id" {
  default = "433568766270"
}

variable "child_account_id" {}

variable "common_name" {}

variable "child_account_region" {
  default = "us-east-1"
}

variable "aws_region" {
  default = "us-east-1"
}

variable "elasticsearch_domain" {
  default = "commons-logs"
}

variable "aws_access_key"{
  default = ""
}

variable "aws_secret_key"{
  default = ""
}

variable "threshold"{}

variable "slack_webhook"{
  default = ""
}

variable "log_dna_function"{
  description = "Lambda function ARN for logDNA"
  default     = ""
}

variable "timeout" {
  description = "Timeout threshold for the function"
  default     = 300
}

variable "memory_size" {
  description = "Memory allocation for the function"
  default     = 128
}
