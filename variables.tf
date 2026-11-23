variable "aws_region" {
  description = "Target AWS region. Defaults to eu-west-1 (Ireland), which provides the lowest latency (~75-95ms) from Nigeria to a non-opt-in region offering m7i-flex instances."
  type        = string
  default     = "eu-west-1"
}

variable "instance_type" {
  description = "Workstation instance type. Prioritizes m7i-flex.large for high single-thread responsiveness and memory, with fallbacks to c7i-flex.large or t3.small."
  type        = string
  default     = "m7i-flex.large"

  validation {
    condition     = contains(["m7i-flex.large", "c7i-flex.large", "t3.small"], var.instance_type)
    error_message = "The instance_type variable must be one of: m7i-flex.large, c7i-flex.large, or t3.small."
  }
}

variable "allowed_ip" {
  description = "Your client workstation public IP address in CIDR /32 format (e.g., '197.210.65.12/32'). Remote desktop and SSH ports are restricted to this single IP."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$", var.allowed_ip)) && var.allowed_ip != "0.0.0.0/0"
    error_message = "The allowed_ip variable must be a valid single IPv4 address in CIDR /32 format (e.g., '203.0.113.15/32') and cannot be 0.0.0.0/0."
  }
}

variable "ssh_public_key" {
  description = "The public SSH key content (e.g. contents of ~/.ssh/id_ed25519.pub) used for key-based authentication."
  type        = string

  validation {
    condition     = can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp[0-9]+)", var.ssh_public_key))
    error_message = "The ssh_public_key must be a valid OpenSSH public key starting with ssh-rsa, ssh-ed25519, or ecdsa-sha2-nistp."
  }
}

variable "workstation_user" {
  description = "The non-root desktop and remote DCV session username."
  type        = string
  default     = "dcvuser"
}

variable "dcv_password" {
  description = "Password for the workstation user for authenticating against the Amazon DCV remote desktop session."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.dcv_password) >= 12
    error_message = "The dcv_password must be at least 12 characters long."
  }
}

variable "budget_notification_email" {
  description = "Email address to receive AWS Budget threshold notifications (at 50%, 80%, and 100% of the allocated monthly credit budget)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", var.budget_notification_email))
    error_message = "budget_notification_email must be a valid email address."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly budget limit in USD. For a ~$200 credit over 6 months, ~33-35 USD/month represents the maximum sustainable burn rate."
  type        = number
  default     = 35.0
}
