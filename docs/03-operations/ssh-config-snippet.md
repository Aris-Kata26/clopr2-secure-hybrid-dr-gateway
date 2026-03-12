# SSH config snippet for vm-pg-dr (Azure DR VM via WireGuard ProxyJump)
#
# Add the block below to ~/.ssh/config (on your WSL/local machine).
# vm-pg-dr is only reachable after:
#   1. WireGuard tunnel is up between pg-primary and Azure DR VM
#   2. pg-primary SSH entry already exists in ~/.ssh/config
#
# Append to ~/.ssh/config:
# -------------------------------------------------
Host vm-pg-dr
  HostName 10.200.0.2
  User azureuser
  IdentityFile ~/.ssh/id_ed25519_dr
  ProxyJump pg-primary
  StrictHostKeyChecking no
# -------------------------------------------------
#
# How to apply:
#   cat docs/03-operations/ssh-config-snippet.md | grep -A7 'Host vm-pg-dr' >> ~/.ssh/config
# Or paste the Host block manually.
#
# Verify tunnel and SSH connectivity:
#   ssh pg-primary 'ping -c 3 10.200.0.2'     # tunnel reachable from pg-primary
#   ssh vm-pg-dr 'wg show wg0'                 # WireGuard status on Azure VM
