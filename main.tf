# ==============================================================================
# main.tf - AWS Remote Desktop Workstation Infrastructure
# ==============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "PersonalWorkstation"
      ManagedBy   = "Terraform"
      Environment = "Dev"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. NETWORK & VPC DISCOVERY
# ------------------------------------------------------------------------------
# We discover the AWS default VPC and subnets to eliminate unnecessary NAT
# gateway and VPC endpoint costs that quickly deplete promotional credits.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ------------------------------------------------------------------------------
# 2. CANONICAL UBUNTU 24.04 LTS (NOBLE NUMBAT) AMI LOOKUP
# ------------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical official account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------------------------
# 3. LEAST-PRIVILEGE IAM ROLE & INSTANCE PROFILE
# ------------------------------------------------------------------------------
# Strictly avoids root keys. Grants:
# 1. AWS Systems Manager (SSM) Session Manager access.
# 2. Permission for the instance to stop only itself when idle.
resource "aws_iam_role" "workstation_role" {
  name = "workstation-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Standard SSM policy for secure agent-based shell & port forwarding
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.workstation_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Scoped policy: allow EC2 instance to stop itself without broader EC2 access
resource "aws_iam_role_policy" "stop_self" {
  name = "workstation-allow-stop-self"
  role = aws_iam_role.workstation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowSelfStopOnly"
        Effect   = "Allow"
        Action   = "ec2:StopInstances"
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Name" = "Personal-Desktop-Workstation"
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "workstation_profile" {
  name = "workstation-instance-profile"
  role = aws_iam_role.workstation_role.name
}

# ------------------------------------------------------------------------------
# 4. SECURITY GROUP
# ------------------------------------------------------------------------------
# Restricts incoming connections to the user's explicit /32 IP address only.
# Never allows 0.0.0.0/0 on sensitive administrative or remote desktop ports.
resource "aws_security_group" "workstation_sg" {
  name        = "workstation-sg"
  description = "Allows Amazon DCV and SSH exclusively from the verified user IP"
  vpc_id      = data.aws_vpc.default.id

  # Amazon DCV HTTPS & WebSocket (TCP 8443)
  ingress {
    description = "Amazon DCV Web & TCP Streaming"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
  }

  # Amazon DCV QUIC Protocol (UDP 8443) - Critical for smooth 60 FPS streaming
  ingress {
    description = "Amazon DCV QUIC UDP Streaming"
    from_port   = 8443
    to_port     = 8443
    protocol    = "udp"
    cidr_blocks = [var.allowed_ip]
  }

  # SSH Key-based login (TCP 22)
  ingress {
    description = "Secure Shell access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
  }

  # Outbound access for package updates and internet browsing
  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# 5. SSH KEY PAIR
# ------------------------------------------------------------------------------
resource "aws_key_pair" "workstation_key" {
  key_name   = "personal-workstation-key"
  public_key = var.ssh_public_key
}

# ------------------------------------------------------------------------------
# 6. EC2 WORKSTATION INSTANCE
# ------------------------------------------------------------------------------
resource "aws_instance" "workstation" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.instance_type
  subnet_id            = tolist(data.aws_subnets.default.ids)[0]
  key_name             = aws_key_pair.workstation_key.key_name
  iam_instance_profile = aws_iam_instance_profile.workstation_profile.name

  vpc_security_group_ids = [aws_security_group.workstation_sg.id]

  # Dynamic ephemeral public IP allocated only when running (avoids Elastic IP idle fees)
  associate_public_ip_address = true

  # Encrypted 30 GB gp3 root block device
  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
    tags = {
      Name = "workstation-root-gp3"
    }
  }

  # Cloud-init bootstrap template
  user_data = templatefile("${path.module}/scripts/user_data.sh", {
    workstation_user = var.workstation_user
    dcv_password     = var.dcv_password
  })

  user_data_replace_on_change = false

  # IMDSv2 strictly enforced (SSRF defense)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "Personal-Desktop-Workstation"
  }
}

# ------------------------------------------------------------------------------
# 7. CLOUDWATCH ALARM (INFRASTRUCTURE SAFETY NET FOR AUTO-STOP)
# ------------------------------------------------------------------------------
# If the EC2 CPU utilization remains below 3.5% for 30 consecutive minutes
# (6 consecutive 5-minute periods), AWS will issue an ec2:stop API action.
resource "aws_cloudwatch_metric_alarm" "auto_stop_idle" {
  alarm_name          = "workstation-auto-stop-when-idle"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 6
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 3.5
  alarm_description   = "Auto-stops EC2 instance when CPU utilization remains low for 30 minutes to preserve credits"
  alarm_actions       = ["arn:aws:automate:${var.aws_region}:ec2:stop"]

  dimensions = {
    InstanceId = aws_instance.workstation.id
  }
}

# ------------------------------------------------------------------------------
# 8. AWS BUDGET ALERTS (50%, 80%, 100%)
# ------------------------------------------------------------------------------
# Proactively protects your promotional credits with automated email thresholds.
resource "aws_budgets_budget" "monthly_workstation_budget" {
  count             = var.enable_budget ? 1 : 0
  name              = "monthly-workstation-credit-budget"
  budget_type       = "COST"
  limit_amount      = tostring(var.monthly_budget_usd)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2025-07-01_00:00"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_notification_email]
  }
}
