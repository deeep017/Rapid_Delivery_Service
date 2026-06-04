# VARIABLES

variable "aws_region" {
  description = "AWS Region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "my_ip" {
  description = "Your local IP address (for SSH access)"
  type        = string
}

variable "db_password" {
  description = "Password for the PostgreSQL database"
  type        = string
  default     = "password123"
  sensitive   = true
}

variable "public_key_path" {
  description = "Path to your SSH public key"
  type        = string
  default     = "k3s-key.pub"
}

variable "instance_type" {
  description = "EC2 instance type for master node (free tier eligible)"
  type        = string
  default     = "t3.micro" # Free tier - 1GB RAM, using swap for DBs
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker node"
  type        = string
  default     = "t3.micro" # Can use micro since no DBs here
}
