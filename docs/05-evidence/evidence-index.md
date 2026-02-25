# Evidence Index

This index tracks proof artifacts required for weekly teacher reviews and the final report.

## How to use this file
- Each user story has required evidence.
- Store screenshots in [docs/05-evidence/screenshots/](docs/05-evidence/screenshots/)
- Store command outputs in [docs/05-evidence/outputs/](docs/05-evidence/outputs/)
- Update weekly progress notes each Friday.

Weekly progress: [docs/05-evidence/week-1-progress.md](docs/05-evidence/week-1-progress.md)

| User Story | Evidence to collect | Where stored | How to verify |
| --- | --- | --- | --- |
| US1 Architecture | Approved architecture screenshot + updated proposal notes | [docs/05-evidence/screenshots/](docs/05-evidence/screenshots/), [docs/05-evidence/outputs/](docs/05-evidence/outputs/) | Review screenshot and notes for alignment to final design |
| US2 Entra/RBAC | Group list + role assignments + screenshots | [docs/05-evidence/screenshots/entra-groups.png](docs/05-evidence/screenshots/entra-groups.png), [docs/05-evidence/screenshots/rbac-assignments.png](docs/05-evidence/screenshots/rbac-assignments.png), [docs/05-evidence/outputs/rbac-assignments.txt](docs/05-evidence/outputs/rbac-assignments.txt) | Verify groups and role assignments match RBAC model |
| US3 AKS | kubectl get deploy/svc/ingress + public URL + screenshot | [docs/05-evidence/outputs/](docs/05-evidence/outputs/), [docs/05-evidence/screenshots/](docs/05-evidence/screenshots/) | Confirm app reachable and resources present |
| US4 On-prem Docker | docker ps + compose file + health URL + screenshot | [docs/05-evidence/outputs/](docs/05-evidence/outputs/), [docs/05-evidence/screenshots/](docs/05-evidence/screenshots/) | Validate containers and health endpoint |
| US5 DB DR | DB primary on-prem + standby replica + VIP; Azure VM DR replica; connectivity tests from both environments; teacher approval (cost caution) | [docs/05-evidence/outputs/terraform-onprem-plan.txt](docs/05-evidence/outputs/terraform-onprem-plan.txt), [docs/05-evidence/outputs/terraform-onprem-apply.txt](docs/05-evidence/outputs/terraform-onprem-apply.txt), [docs/05-evidence/outputs/ansible-ping.txt](docs/05-evidence/outputs/ansible-ping.txt), [docs/05-evidence/outputs/ansible-site-run.txt](docs/05-evidence/outputs/ansible-site-run.txt), [docs/05-evidence/screenshots/proxmox-vms-created.png](docs/05-evidence/screenshots/proxmox-vms-created.png), [docs/05-evidence/screenshots/proxmox-vm-cloudinit.png](docs/05-evidence/screenshots/proxmox-vm-cloudinit.png), [docs/05-evidence/screenshots/teacher-approval-cost-caution.png](docs/05-evidence/screenshots/teacher-approval-cost-caution.png) | Confirm on-prem VIP, replication status, and Azure DR reachability |
| US6 VPN | Gateway config + routing checks + replication/app connectivity to Azure VM DR replica + screenshots | [docs/05-evidence/outputs/](docs/05-evidence/outputs/), [docs/05-evidence/screenshots/](docs/05-evidence/screenshots/) | Validate private routes and DB replication/app traffic paths |
| US7 Monitoring | Log Analytics queries baseline screenshots | [docs/05-evidence/screenshots/loganalytics-overview.png](docs/05-evidence/screenshots/loganalytics-overview.png), [docs/05-evidence/screenshots/kql-search.png](docs/05-evidence/screenshots/kql-search.png), [docs/05-evidence/screenshots/kql-azureactivity.png](docs/05-evidence/screenshots/kql-azureactivity.png) | Verify query output and Log Analytics baseline |
| CI baseline | GitHub Actions CI baseline success screenshot | [docs/05-evidence/screenshots/ci-baseline.png](docs/05-evidence/screenshots/ci-baseline.png) | Confirm workflows pass with green checks |
| US8 IaC | terraform validate output + repo workflows passing + screenshots | [docs/05-evidence/outputs/terraform-validate.txt](docs/05-evidence/outputs/terraform-validate.txt), [docs/05-evidence/screenshots/terraform-validate.png](docs/05-evidence/screenshots/terraform-validate.png), [docs/05-evidence/screenshots/ci-terraform.png](docs/05-evidence/screenshots/ci-terraform.png), [docs/05-evidence/screenshots/rg-resources-gwc.png](docs/05-evidence/screenshots/rg-resources-gwc.png) | Confirm validate output and green CI checks |
| US9 Security | Key Vault usage + Defender recommendations + NSG rules evidence | [docs/05-evidence/screenshots/defender-enabled.png](docs/05-evidence/screenshots/defender-enabled.png), [docs/05-evidence/screenshots/secure-score.png](docs/05-evidence/screenshots/secure-score.png), [docs/05-evidence/screenshots/recommendations-by-title.png](docs/05-evidence/screenshots/recommendations-by-title.png) | Recommendation titles captured (View by title). Remediation scheduled for later sprint. |
| US10 Cost/tags | Cost analysis + budget screenshot | [docs/05-evidence/screenshots/cost-analysis.png](docs/05-evidence/screenshots/cost-analysis.png), [docs/05-evidence/screenshots/budget-alert.png](docs/05-evidence/screenshots/budget-alert.png) | Verify cost governance evidence |
| US11 Final | Report draft + presentation outline + rehearsal notes | [docs/05-evidence/outputs/](docs/05-evidence/outputs/) | Review completeness of final artifacts |
