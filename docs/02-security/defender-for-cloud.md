# Defender for Cloud baseline (AZ-500)

## Purpose
Establish early security posture management (AZ-500) with visibility into secure score and recommendations for the project scope.

## Scope and compliance
- Scope: Subscription-level baseline with focus on RG `rg-clopr2-katar711-gwc`.
- Region compliance: Germany West Central (EU-only requirement).

## What was enabled
- Microsoft Defender for Cloud baseline (Foundational CSPM / Free plan).
- Paid Defender plans remain disabled to avoid unnecessary cost at this stage.

## Secure score snapshot
Secure score provides a high-level view of posture. At this early baseline, scores may be low or incomplete until more services emit signals.

## Observed recommendations (Sprint 1)
- Disabled accounts with owner permissions on Azure resources should be removed
- Guest accounts with read permissions on Azure resources should be removed
- There should be more than one owner assigned to subscriptions
- Guest accounts with write permissions on Azure resources should be removed
- Subnets should be associated with a network security group
- Disabled accounts with read and write permissions on Azure resources should be removed
- A maximum of 3 owners should be designated for subscriptions
- Guest accounts with owner permissions on Azure resources should be removed
- Azure DDoS Protection Standard should be enabled

These recommendations are now visible after enabling Defender CSPM. Remediation will be planned and implemented in Sprint 4 with evidence.

## Evidence
- docs/05-evidence/screenshots/defender-enabled.png
- docs/05-evidence/screenshots/secure-score.png
- docs/05-evidence/screenshots/recommendations.png
- docs/05-evidence/screenshots/recommendations-by-title.png