#!/usr/bin/env bash
# gcp-proof-deploy.sh
# ====================
# Run this in GCP Cloud Shell to deploy the CLOPR2 GCP proof-of-portability.
#
# Pre-requisites (already met in Cloud Shell):
#   gcloud auth list            → akatagaruka@gmail.com ACTIVE
#   gcloud config get-value project → aris-project-490607
#
# Usage:
#   git clone https://github.com/Aris-Kata26/clopr2-secure-hybrid-dr-gateway.git
#   cd clopr2-secure-hybrid-dr-gateway
#   bash scripts/portability/gcp-proof-deploy.sh
#
# Teardown:
#   terraform -chdir=infra/terraform/envs/gcp-proof destroy -auto-approve

set -euo pipefail

PROJECT_ID="aris-project-490607"
REGION="europe-west3"
PROOF_DIR="infra/terraform/envs/gcp-proof"

echo "======================================================"
echo "CLOPR2 GCP Proof-of-Portability Deploy"
echo "Project: $PROJECT_ID | Region: $REGION"
echo "Date:    $(date -u)"
echo "======================================================"

# ── Step 1: Set project ────────────────────────────────────────────────────────
echo ""
echo "=== Step 1: Set active GCP project ==="
gcloud config set project "$PROJECT_ID"
gcloud config get-value project

# ── Step 2: Enable required APIs ──────────────────────────────────────────────
echo ""
echo "=== Step 2: Enable required GCP APIs ==="
gcloud services enable compute.googleapis.com --project="$PROJECT_ID"
gcloud services enable iam.googleapis.com --project="$PROJECT_ID"
echo "APIs enabled."

# ── Step 3: Configure application default credentials ─────────────────────────
echo ""
echo "=== Step 3: Configure Terraform credentials ==="
# In Cloud Shell, ADC is auto-configured from gcloud auth.
# If not, uncomment:
# gcloud auth application-default login
gcloud auth application-default print-access-token | head -c 20 | xargs -I{} echo "ADC token present: {}..."

# ── Step 4: Install Terraform if not present ───────────────────────────────────
echo ""
echo "=== Step 4: Check Terraform ==="
if ! command -v terraform &> /dev/null; then
    echo "Installing Terraform..."
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
    sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
    sudo apt-get update -qq && sudo apt-get install -y terraform
fi
terraform version

# ── Step 5: Terraform init ────────────────────────────────────────────────────
echo ""
echo "=== Step 5: Terraform init ==="
terraform -chdir="$PROOF_DIR" init

# ── Step 6: Terraform plan ────────────────────────────────────────────────────
echo ""
echo "=== Step 6: Terraform plan ==="
terraform -chdir="$PROOF_DIR" plan -out=tfplan

# ── Step 7: Terraform apply ───────────────────────────────────────────────────
echo ""
echo "=== Step 7: Terraform apply ==="
terraform -chdir="$PROOF_DIR" apply tfplan

# ── Step 8: Capture outputs ───────────────────────────────────────────────────
echo ""
echo "=== Step 8: Outputs (evidence) ==="
terraform -chdir="$PROOF_DIR" output -json | tee /tmp/gcp-proof-outputs.json

INSTANCE_ID=$(terraform -chdir="$PROOF_DIR" output -raw instance_id 2>/dev/null || echo "unknown")
INSTANCE_NAME=$(terraform -chdir="$PROOF_DIR" output -raw instance_name)
PUBLIC_IP=$(terraform -chdir="$PROOF_DIR" output -raw public_ip)
PRIVATE_IP=$(terraform -chdir="$PROOF_DIR" output -raw private_ip)
SA_EMAIL=$(terraform -chdir="$PROOF_DIR" output -raw service_account_email)

# ── Step 9: Verify instance running ──────────────────────────────────────────
echo ""
echo "=== Step 9: Verify instance state ==="
gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="${REGION}-b" \
    --format="table(name,status,machineType.basename(),networkInterfaces[0].accessConfigs[0].natIP,networkInterfaces[0].networkIP)"

# ── Step 10: Write evidence file ──────────────────────────────────────────────
EVIDENCE_FILE="docs/05-evidence/portability/gcp-proof-deploy.txt"
mkdir -p "$(dirname "$EVIDENCE_FILE")"
cat > "$EVIDENCE_FILE" <<EOF
GCP Proof-of-Portability — Deployment Evidence
================================================
Date:         $(date -u)
Project:      $PROJECT_ID
Region:       $REGION
Zone:         ${REGION}-b

Instance Name:  $INSTANCE_NAME
Instance ID:    $INSTANCE_ID
Public IP:      $PUBLIC_IP
Private IP:     $PRIVATE_IP
Service Account: $SA_EMAIL

Machine type:   e2-micro
OS:             Ubuntu 22.04 LTS (ubuntu-os-cloud/ubuntu-2204-lts)
Disk:           20 GB pd-standard
Network:        clopr2-proof-vpc (10.22.0.0/16)
Subnet:         clopr2-proof-subnet (10.22.1.0/24)
Firewall:       WireGuard UDP 51820 open (proof scope)

Equivalence to Azure:
  google_compute_instance    → azurerm_linux_virtual_machine
  google_service_account     → SystemAssigned Managed Identity
  google_compute_network     → azurerm_virtual_network
  google_compute_firewall    → azurerm_network_security_group
  google_compute_address     → azurerm_public_ip (Static)

Bootstrap (user-data/startup-script):
  Installs: wireguard, postgresql-client-16
  Proof marker: /etc/clopr2-proof
  Log: /var/log/clopr2-proof-init.log

Teardown:
  terraform -chdir=infra/terraform/envs/gcp-proof destroy -auto-approve

Status: DEPLOYED
EOF

echo ""
echo "Evidence written to: $EVIDENCE_FILE"
echo ""
echo "======================================================"
echo "GCP Proof-of-Portability: COMPLETE"
echo "Instance: $INSTANCE_NAME | IP: $PUBLIC_IP"
echo "======================================================"
echo ""
echo "TEARDOWN when done:"
echo "  terraform -chdir=$PROOF_DIR destroy -auto-approve"
