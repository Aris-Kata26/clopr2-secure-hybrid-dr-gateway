#!/usr/bin/env bash
# wg-keygen.sh — Generate WireGuard keypairs for both tunnel peers.
#
# Outputs:
#   /tmp/wg-keys/onprem-wg-privkey  (secret — for pg-primary ansible-vault)
#   /tmp/wg-keys/onprem-wg-pubkey   (public — fill in terraform.tfvars as wg_onprem_pubkey)
#   /tmp/wg-keys/azure-wg-privkey   (secret — set as TF_VAR_wg_azure_privkey)
#   /tmp/wg-keys/azure-wg-pubkey    (public — for vm_pg_dr ansible-vault wg_peer_pubkey)
#
# Usage: bash scripts/wg-keygen.sh
set -euo pipefail

KEY_DIR="/tmp/wg-keys"
mkdir -p "${KEY_DIR}"
chmod 700 "${KEY_DIR}"

# Generate on-prem (pg-primary) keypair
wg genkey > "${KEY_DIR}/onprem-wg-privkey"
wg pubkey < "${KEY_DIR}/onprem-wg-privkey" > "${KEY_DIR}/onprem-wg-pubkey"

# Generate Azure DR VM keypair
wg genkey > "${KEY_DIR}/azure-wg-privkey"
wg pubkey < "${KEY_DIR}/azure-wg-privkey" > "${KEY_DIR}/azure-wg-pubkey"

chmod 600 "${KEY_DIR}/onprem-wg-privkey" "${KEY_DIR}/azure-wg-privkey"
chmod 644 "${KEY_DIR}/onprem-wg-pubkey"  "${KEY_DIR}/azure-wg-pubkey"

ONPREM_PUBKEY=$(cat "${KEY_DIR}/onprem-wg-pubkey")
AZURE_PUBKEY=$(cat  "${KEY_DIR}/azure-wg-pubkey")
ONPREM_PRIVKEY=$(cat "${KEY_DIR}/onprem-wg-privkey")
AZURE_PRIVKEY=$(cat  "${KEY_DIR}/azure-wg-privkey")

echo ""
echo "=== WireGuard keypairs generated ==="
echo ""
echo "--- On-prem (pg-primary) ---"
echo "  Public key  : ${ONPREM_PUBKEY}"
echo "  Private key : ${ONPREM_PRIVKEY}"
echo ""
echo "--- Azure DR VM (vm-pg-dr-fce) ---"
echo "  Public key  : ${AZURE_PUBKEY}"
echo "  Private key : ${AZURE_PRIVKEY}"
echo ""
echo "=== Next steps ==="
echo ""
echo "1. Fill wg_onprem_pubkey in infra/terraform/envs/dr-fce/terraform.tfvars:"
echo "   wg_onprem_pubkey = \"${ONPREM_PUBKEY}\""
echo ""
echo "2. Export Azure private key for Terraform (in the same shell that runs terraform apply):"
echo "   export TF_VAR_wg_azure_privkey='${AZURE_PRIVKEY}'"
echo ""
echo "3. After terraform apply, get the Azure VM public IP:"
echo "   cd infra/terraform/envs/dr-fce && terraform output pg_dr_wg_public_ip"
echo "   Update wg_peer_endpoint in infra/ansible/inventories/dev/group_vars/pg_primary.yml"
echo ""
echo "4. Store private keys in Ansible vault — run from repo root:"
echo "   ansible-vault encrypt_string '${ONPREM_PRIVKEY}' --name wg_privkey"
echo "     → paste output into inventories/dev/group_vars/pg_primary.yml"
echo "   ansible-vault encrypt_string '${AZURE_PRIVKEY}' --name wg_privkey"
echo "     → paste output into inventories/dev/group_vars/vm_pg_dr.yml"
echo ""
echo "5. Store peer public keys (plain text is fine — they are not secret):"
echo "   In pg_primary.yml:  wg_peer_pubkey: \"${AZURE_PUBKEY}\""
echo "   In vm_pg_dr.yml:    wg_peer_pubkey: \"${ONPREM_PUBKEY}\""
echo ""
echo "Key files saved to: ${KEY_DIR}/ (delete after vaulting)"
