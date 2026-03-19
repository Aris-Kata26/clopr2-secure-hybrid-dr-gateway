# providers/aws/compute-db — AWS DR Database VM
# ================================================
# STATUS: SCAFFOLD — NOT DEPLOYED
# This module is proof-of-portability scaffolding only.
# It has NOT been applied to any AWS account.
# It does NOT affect the validated Azure DR platform.
#
# Implements: shared/compute-db interface
# Target:     EC2 instance running PostgreSQL 16 (DR replica from on-prem primary)
#
# To deploy:
#   1. Set up AWS provider credentials
#   2. Create a tfvars file with required variables (see variables.tf)
#   3. Run: terraform init && terraform plan
#   4. Review plan, then: terraform apply
#
# Pre-requisites before this is production-ready:
#   - AWS VPC + subnet created (providers/aws/core-network/)
#   - WireGuard tunnel verified end-to-end
#   - PostgreSQL streaming replication tested across WireGuard tunnel
#   - ansible-lint and DR scripts validated for AWS SSH targets

# ── Provider ──────────────────────────────────────────────────────────────────

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# provider "aws" {
#   region = var.region
# }

# ── Data sources ──────────────────────────────────────────────────────────────

# data "aws_ami" "ubuntu_2204" {
#   most_recent = true
#   owners      = ["099720109477"] # Canonical
#   filter {
#     name   = "name"
#     values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
#   }
#   filter {
#     name   = "virtualization-type"
#     values = ["hvm"]
#   }
# }

# ── IAM — Instance Profile ────────────────────────────────────────────────────
# Equivalent to Azure SystemAssigned Managed Identity

# resource "aws_iam_role" "pg_dr" {
#   name = "clopr2-pg-dr-${var.env_name}"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "ec2.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
#   tags = var.tags
# }

# resource "aws_iam_instance_profile" "pg_dr" {
#   name = "clopr2-pg-dr-${var.env_name}"
#   role = aws_iam_role.pg_dr.name
# }

# ── Network Interface ─────────────────────────────────────────────────────────

# resource "aws_network_interface" "pg_dr" {
#   subnet_id       = var.subnet_id
#   private_ips     = var.private_ip != null ? [var.private_ip] : []
#   security_groups = [aws_security_group.pg_dr.id]
#   tags = merge(var.tags, { Name = "clopr2-pg-dr-nic-${var.env_name}" })
# }

# resource "aws_eip" "pg_dr" {
#   domain                    = "vpc"
#   network_interface         = aws_network_interface.pg_dr.id
#   associate_with_private_ip = var.private_ip
#   tags = merge(var.tags, { Name = "clopr2-pg-dr-eip-${var.env_name}" })
# }

# ── Security Group ────────────────────────────────────────────────────────────
# Equivalent to Azure NSG

# resource "aws_security_group" "pg_dr" {
#   name        = "clopr2-pg-dr-sg-${var.env_name}"
#   description = "Security group for CLOPR2 DR database VM"
#   vpc_id      = var.vpc_id
#
#   # WireGuard UDP inbound from on-prem public IP only
#   ingress {
#     from_port   = var.wg_listen_port
#     to_port     = var.wg_listen_port
#     protocol    = "udp"
#     cidr_blocks = ["${var.wg_onprem_public_ip}/32"]
#     description = "WireGuard from on-prem"
#   }
#
#   # SSH via WireGuard tunnel only (not public)
#   ingress {
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = ["${split("/", var.wg_tunnel_ip)[0]}/32"]  # on-prem tunnel IP
#     description = "SSH via WireGuard tunnel"
#   }
#
#   # PostgreSQL from WireGuard tunnel
#   ingress {
#     from_port   = 5432
#     to_port     = 5432
#     protocol    = "tcp"
#     cidr_blocks = ["10.200.0.0/24"]
#     description = "PostgreSQL from WireGuard tunnel"
#   }
#
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#
#   tags = merge(var.tags, { Name = "clopr2-pg-dr-sg-${var.env_name}" })
# }

# ── Key Pair ──────────────────────────────────────────────────────────────────

# resource "aws_key_pair" "pg_dr" {
#   key_name   = "clopr2-pg-dr-${var.env_name}"
#   public_key = var.ssh_public_key
#   tags       = var.tags
# }

# ── Cloud-Init (user_data) ────────────────────────────────────────────────────
# Equivalent to Azure custom_data cloud-init
# Installs WireGuard, configures wg0, sets up PostgreSQL standby

# locals {
#   cloud_init = <<-CLOUDINIT
#     #cloud-config
#     packages:
#       - wireguard
#       - postgresql-16
#     write_files:
#       - path: /etc/wireguard/wg0.conf
#         permissions: '0600'
#         content: |
#           [Interface]
#           PrivateKey = ${var.wg_private_key}
#           Address    = ${var.wg_tunnel_ip}
#           ListenPort = ${var.wg_listen_port}
#           [Peer]
#           PublicKey    = ${var.wg_peer_public_key}
#           AllowedIPs   = 10.0.0.0/16,10.200.0.0/24
#           Endpoint     = ${var.wg_onprem_public_ip}:51820
#           PersistentKeepalive = 25
#     runcmd:
#       - systemctl enable --now wg-quick@wg0
#   CLOUDINIT
# }

# ── EC2 Instance ──────────────────────────────────────────────────────────────

# resource "aws_instance" "pg_dr" {
#   ami                    = data.aws_ami.ubuntu_2204.id
#   instance_type          = var.vm_size
#   key_name               = aws_key_pair.pg_dr.key_name
#   iam_instance_profile   = aws_iam_instance_profile.pg_dr.name
#   user_data_base64       = base64encode(local.cloud_init)
#
#   network_interface {
#     network_interface_id = aws_network_interface.pg_dr.id
#     device_index         = 0
#   }
#
#   root_block_device {
#     volume_size           = var.disk_size_gb
#     volume_type           = "gp3"
#     delete_on_termination = true
#   }
#
#   tags = merge(var.tags, { Name = "clopr2-pg-dr-${var.env_name}" })
# }
