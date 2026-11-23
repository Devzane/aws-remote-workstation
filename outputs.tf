# ==============================================================================
# outputs.tf - Workstation Connection and Management Outputs
# ==============================================================================

output "instance_id" {
  description = "The EC2 Instance ID of the workstation"
  value       = aws_instance.workstation.id
}

output "public_ip" {
  description = "Public IPv4 address assigned to the workstation"
  value       = aws_instance.workstation.public_ip
}

output "dcv_web_url" {
  description = "Direct HTTPS URL to access the Amazon DCV web console"
  value       = "https://${aws_instance.workstation.public_ip}:8443"
}

output "dcv_client_target" {
  description = "Host and port string for connecting via the native Amazon DCV Client application"
  value       = "${aws_instance.workstation.public_ip}:8443"
}

output "ssh_connection_string" {
  description = "Direct SSH command to connect to the workstation desktop user"
  value       = "ssh -i <path-to-private-key> ${var.workstation_user}@${aws_instance.workstation.public_ip}"
}

output "ssh_admin_connection_string" {
  description = "Direct SSH command to connect as default administrative user (ubuntu)"
  value       = "ssh -i <path-to-private-key> ubuntu@${aws_instance.workstation.public_ip}"
}

output "ssm_shell_command" {
  description = "AWS CLI SSM Session Manager command to open an interactive terminal without open inbound ports"
  value       = "aws ssm start-session --target ${aws_instance.workstation.id} --region ${var.aws_region}"
}

output "ssm_port_forward_dcv" {
  description = "Tunnel Amazon DCV port 8443 securely over SSM to your local machine (zero open ports in SG)"
  value       = "aws ssm start-session --target ${aws_instance.workstation.id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"8443\"],\"localPortNumber\":[\"8443\"]}' --region ${var.aws_region}"
}

output "stop_workstation_command" {
  description = "AWS CLI command to manually stop the workstation when done working"
  value       = "aws ec2 stop-instances --instance-ids ${aws_instance.workstation.id} --region ${var.aws_region}"
}

output "start_workstation_command" {
  description = "AWS CLI command to start the workstation"
  value       = "aws ec2 start-instances --instance-ids ${aws_instance.workstation.id} --region ${var.aws_region}"
}
