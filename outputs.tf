# ==============================================================================
# outputs.tf - Windows Workstation Connection and Management Outputs
# ==============================================================================

output "instance_id" {
  description = "The EC2 Instance ID of the workstation"
  value       = aws_instance.workstation.id
}

output "public_ip" {
  description = "Public IPv4 address assigned to the workstation"
  value       = aws_instance.workstation.public_ip
}

output "rdp_command" {
  description = "Standard Remote Desktop Connection command"
  value       = "mstsc /v:${aws_instance.workstation.public_ip}"
}

output "rdp_fullscreen_command" {
  description = "Fullscreen Remote Desktop Connection command (pixel-perfect native scaling)"
  value       = "mstsc /v:${aws_instance.workstation.public_ip} /f"
}

output "admin_username" {
  description = "Default Windows administrative user"
  value       = "Administrator"
}

output "ssm_shell_command" {
  description = "AWS CLI SSM Session Manager command to open an interactive terminal without open inbound ports"
  value       = "aws ssm start-session --target ${aws_instance.workstation.id} --region ${var.aws_region}"
}

output "stop_workstation_command" {
  description = "AWS CLI command to manually stop the workstation when done working"
  value       = "aws ec2 stop-instances --instance-ids ${aws_instance.workstation.id} --region ${var.aws_region}"
}

output "start_workstation_command" {
  description = "AWS CLI command to start the workstation"
  value       = "aws ec2 start-instances --instance-ids ${aws_instance.workstation.id} --region ${var.aws_region}"
}
