# envs/aws-proof — AWS Proof-of-Portability
# ===========================================
# PURPOSE: Minimal isolated proof that the CLOPR2 DR VM pattern provisions
#          correctly on AWS. Not a production DR environment.
#
# SCOPE:   Isolated — entirely independent of the validated Azure platform.
#          Uses its own VPC, SG, key pair. No Azure resources touched.
#
# TEARDOWN: terraform destroy (removes all resources in this env)
#
# Maps to:  shared/compute-db interface contract
# Scaffold: providers/aws/compute-db/ (uncommented here for proof)
#
# Date:     2026-03-19 | Author: KATAR711 | Team: BCLC24

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Local state — proof only. No remote backend for this isolated proof.
}

provider "aws" {
  region = var.region
}

# ── VPC (isolated, CIDR does not overlap Azure or on-prem) ───────────────────

resource "aws_vpc" "proof" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name    = "clopr2-proof-vpc"
    purpose = "portability-proof"
  })
}

resource "aws_internet_gateway" "proof" {
  vpc_id = aws_vpc.proof.id
  tags = merge(var.tags, { Name = "clopr2-proof-igw" })
}

resource "aws_subnet" "proof" {
  vpc_id                  = aws_vpc.proof.id
  cidr_block              = var.subnet_cidr
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = merge(var.tags, { Name = "clopr2-proof-subnet" })
}

resource "aws_route_table" "proof" {
  vpc_id = aws_vpc.proof.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.proof.id
  }

  tags = merge(var.tags, { Name = "clopr2-proof-rt" })
}

resource "aws_route_table_association" "proof" {
  subnet_id      = aws_subnet.proof.id
  route_table_id = aws_route_table.proof.id
}

# ── Security Group ────────────────────────────────────────────────────────────
# Equivalent to Azure NSG on the DR VM.
# WireGuard UDP open for proof; SSH closed (no direct internet access).

resource "aws_security_group" "proof" {
  name        = "clopr2-proof-sg"
  description = "CLOPR2 AWS proof-of-portability DR VM"
  vpc_id      = aws_vpc.proof.id

  # WireGuard UDP — equivalent to Azure NSG rule "wireguard-inbound"
  ingress {
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "WireGuard UDP - proof only, production restricts to on-prem public IP"
  }

  # All outbound (for apt-get during bootstrap)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "clopr2-proof-sg" })
}

# ── SSH Key Pair ──────────────────────────────────────────────────────────────

resource "aws_key_pair" "proof" {
  key_name   = "clopr2-proof-key"
  public_key = var.ssh_public_key
  tags       = var.tags
}

# ── AMI — Ubuntu 22.04 LTS ───────────────────────────────────────────────────
# Same OS as Azure DR VM (Ubuntu 22.04, matching Ansible role assumptions)

data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ── Cloud-Init (user_data) ────────────────────────────────────────────────────
# Equivalent to Azure custom_data.
# Installs WireGuard and PostgreSQL client — validates package availability.
# Does NOT configure WireGuard tunnel (no on-prem connection in this proof).
# Does NOT install PostgreSQL server (Ansible would do that).

locals {
  user_data = <<-USERDATA
    #!/bin/bash
    set -euo pipefail
    exec > /var/log/clopr2-proof-init.log 2>&1

    echo "=== CLOPR2 AWS Proof-of-Portability Bootstrap ==="
    echo "Date: $(date -u)"
    echo "Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
    echo "Region:   $(curl -s http://169.254.169.254/latest/meta-data/placement/region)"

    apt-get update -qq
    apt-get install -y wireguard postgresql-client-16 curl 2>&1

    echo ""
    echo "=== Package validation ==="
    wg --version
    psql --version

    echo ""
    echo "=== Proof marker ==="
    echo "clopr2-portability-proof-aws-$(date +%Y%m%d)" > /etc/clopr2-proof
    cat /etc/clopr2-proof

    echo "=== Bootstrap complete ==="
  USERDATA
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────
# Equivalent to azurerm_linux_virtual_machine in envs/dr-fce/main.tf.
# Same logical role: DR DB VM that would host PostgreSQL + WireGuard.

resource "aws_instance" "proof" {
  ami           = data.aws_ami.ubuntu_2204.id
  instance_type = var.vm_size
  key_name      = aws_key_pair.proof.key_name
  subnet_id     = aws_subnet.proof.id

  vpc_security_group_ids      = [aws_security_group.proof.id]
  associate_public_ip_address = true

  user_data                   = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = var.disk_size_gb
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = merge(var.tags, {
    Name    = "clopr2-proof-dr-vm"
    role    = "dr-db-vm"
    purpose = "portability-proof"
    managed = "terraform"
  })
}
