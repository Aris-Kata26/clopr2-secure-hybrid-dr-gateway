# Evidence Index

This index tracks proof artifacts required for weekly teacher reviews and the final report.

## How to use this file
- Each user story has required evidence.
- Store screenshots in docs/05-evidence/screenshots/
- Store command outputs in docs/05-evidence/outputs/
- Update weekly progress notes each Friday.

Weekly progress: docs/05-evidence/week-1-progress.md

| User Story | Evidence to collect | Where stored | How to verify |
| --- | --- | --- | --- |
| US1 Architecture | Approved architecture screenshot + updated proposal notes | docs/05-evidence/screenshots/, docs/05-evidence/outputs/ | Review screenshot and notes for alignment to final design |
| US2 Entra/RBAC | Group list + role assignments + screenshots | docs/05-evidence/screenshots/, docs/05-evidence/outputs/ | Verify groups and role assignments match RBAC model |
| US3 AKS | kubectl get deploy/svc/ingress + public URL + screenshot | docs/05-evidence/outputs/, docs/05-evidence/screenshots/ | Confirm app reachable and resources present |
| US4 On-prem Docker | docker ps + compose file + health URL + screenshot | docs/05-evidence/outputs/, docs/05-evidence/screenshots/ | Validate containers and health endpoint |
| US5 Azure DB | Service config + connectivity tests from both environments + teacher approval reference | docs/05-evidence/outputs/, docs/05-evidence/screenshots/ | Confirm DB reachable from Azure and on-prem |
| US6 VPN | Gateway config + routing checks + ping/curl tests + screenshots | docs/05-evidence/outputs/, docs/05-evidence/screenshots/ | Validate private routes and connectivity |
| US7 Monitoring | Log Analytics queries + alert fired screenshot | docs/05-evidence/outputs/, docs/05-evidence/screenshots/ | Verify query output and alert evidence |
| US8 IaC | terraform plan/apply logs + repo workflows passing | docs/05-evidence/outputs/, .github/workflows/ | Confirm logs and green CI checks |
| US9 Security | Key Vault usage + Defender recommendations + NSG rules evidence | docs/05-evidence/outputs/, docs/05-evidence/screenshots/ | Verify security controls and recommendations |
| US10 Cost/tags | Tags applied + budget/alert screenshot + cost overview | docs/05-evidence/screenshots/, docs/05-evidence/outputs/ | Verify tags and cost governance evidence |
| US11 Final | Report draft + presentation outline + rehearsal notes | docs/05-evidence/outputs/ | Review completeness of final artifacts |
