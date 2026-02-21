# Portal baseline steps (portal-first)

This doc records the manual Azure portal baseline actions done before IaC.

1. Confirm subscription and allowed EU regions to avoid policy blocks.
2. Create the resource group for the baseline to anchor scope and tags.
3. Apply standard tags (Team, Owner, Environment) at RG scope for governance.
4. Review and document region restrictions in policy to pick a compliant region.
5. Create the virtual network and subnets to establish the network envelope.
6. Create NSGs for subnets to enforce least-privilege traffic rules.
7. Enable Log Analytics workspace to centralize monitoring from day one.
8. Enable Defender for Cloud at subscription scope for baseline security posture.
9. Create Key Vault with RBAC to store secrets and future app credentials.
10. Validate RBAC assignments for admin and ops groups at RG scope.
11. Capture screenshots of created resources for evidence tracking.
12. Record any portal errors and fixes in the troubleshooting log.
