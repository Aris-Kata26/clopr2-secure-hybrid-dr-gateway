# Azure Monitor + Log Analytics

## Purpose
Provide a single pane of glass for Azure resource monitoring and a landing zone for future on-prem logs.

## Workspace baseline
- Name: log-clopr2-dev-gwc
- Region: Germany West Central (EU)
- Scope: subscription + resource group (rg-clopr2-katar711-gwc)

## Signals visible now
- AzureActivity table entries for subscription-level operations.
- Generic log search results to confirm query access.

## Next step
On-prem ingestion and custom log sources will be added in Sprint 3/4.

## Evidence
- docs/05-evidence/screenshots/loganalytics-overview.png
- docs/05-evidence/screenshots/kql-search.png
- docs/05-evidence/screenshots/kql-azureactivity.png
