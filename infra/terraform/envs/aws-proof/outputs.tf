# envs/aws-proof — Outputs
# These mirror the shared/compute-db interface contract outputs.

output "instance_id" {
  description = "EC2 instance ID — equivalent to azurerm_linux_virtual_machine.id"
  value       = aws_instance.proof.id
}

output "private_ip" {
  description = "Private IP — equivalent to azurerm_network_interface.private_ip_address"
  value       = aws_instance.proof.private_ip
}

output "public_ip" {
  description = "Public IP (Elastic IP) — equivalent to azurerm_public_ip.ip_address (WireGuard endpoint)"
  value       = aws_instance.proof.public_ip
}

output "ami_id" {
  description = "Ubuntu 22.04 AMI used — confirms same OS as Azure DR VM"
  value       = data.aws_ami.ubuntu_2204.id
}

output "ami_name" {
  description = "AMI name for evidence"
  value       = data.aws_ami.ubuntu_2204.name
}

output "vpc_id" {
  description = "Isolated proof VPC ID"
  value       = aws_vpc.proof.id
}

output "security_group_id" {
  description = "Security group ID — equivalent to azurerm_network_security_group.id"
  value       = aws_security_group.proof.id
}

output "teardown_command" {
  description = "Command to destroy all proof resources"
  value       = "terraform -chdir=infra/terraform/envs/aws-proof destroy -auto-approve"
}
