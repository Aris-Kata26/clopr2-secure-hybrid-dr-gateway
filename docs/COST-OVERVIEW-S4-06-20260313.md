# S4-06 Cost Overview & Optimization Notes

**Date**: 2026-03-13T16:35:00Z UTC  
**Status**: Initial Analysis  
**Scope**: CLOPR2 Hybrid Platform - Full Cost Assessment

---

## Cost Summary - Monthly Breakdown

### Azure DR Infrastructure (DR Resource Group: rg-clopr2-katar711-gwc)

| Component | Resource | SKU/Size | Est. Monthly Cost (USD) | Annual Cost | Essential? |
|-----------|----------|----------|------------------------|-------------|-----------|
| **Compute** | | | | | |
| Azure Arc | pg-primary | Standard_B2s | ~$40 | ~$480 | ✅ Essential (Primary DB) |
| Azure Arc | pg-standby | Standard_B2s | ~$40 | ~$480 | ✅ Essential (Standby/DR) |
| Azure Arc | app-onprem | Standard_B2s | ~$40 | ~$480 | ✅ Essential (App server) |
| **Monitoring/Logging** | | | | | |
| Log Analytics | log-clopr2-dev-gwc | PerGB2018 | ~$50-100* | ~$600-1200 | ⚠️ Configurable |
| Data Collection Rules | DCR (CPU + Memory) | Standard | ~$5 | ~$60 | ✅ Low cost, keep |
| **Data Plane** | | | | | |
| Key Vault | kvclopr2katarweu01gwc | Standard | ~$0.60/operation | ~$20-50 | ✅ Essential (Secrets) |
| Public IP | [AKS Ingress + others] | Static | ~$2.92 each | ~$35 | ⚠️ Can minimize |
| **Orchestration** | | | | | |
| AKS Cluster | [Not found in RG] | - | See Note | - | ⚠️ May be in different RG |
| Traffic Manager | [Not found in RG] | Standard | ~$6 | ~$72 | ⚠️ Verify if used |

**Estimated Total Monthly Cost**: $215-275 USD (excluding AKS + TM)  
**Estimated Annual Cost**: ~$2,580-3,300

*Log Analytics cost varies significantly based on ingestion volume and retention policy

---

## Detailed Cost Analysis by Component

### 1. Azure Arc Machines (High Priority: Core Infrastructure)

**Current State**:
- 3x machines @ Standard_B2s (2 vCPU, 4 GB RAM each)
- Total: ~$120/month for compute
- Plus: Arc agent fee (~$15-20/month for extensions + management)

**Analysis**:
- ✅ **Essential**: These are production DB + app servers
- ⚠️ **Monitor**: Check if B2s is right-sized (evaluate CPU/memory utilization)
- 💡 **Opportunity**: If utilization < 30%, downsize to Standard_B1s (~$25/month each = savings of $45/month)

**Recommendation**: KEEP current sizing unless utilization shows headroom

---

### 2. Log Analytics Workspace (Medium Priority: Controllable)

**Current State**:
- SKU: PerGB2018 (Pay-As-You-Go, ~$2.30/GB ingested)
- Workspace: log-clopr2-dev-gwc
- Retention: [TO BE VERIFIED - check workspace settings]

**Estimated Monthly Ingestion** (based on typical dev environment):
- Heartbeat: ~1-2 GB/month (3 machines)
- Perf counters: ~2-3 GB/month
- Custom logs: ~1-2 GB/month
- **Total**: ~5-7 GB/month = ~$12-16/month (unlikely to exceed $50)

**Analysis**:
- ⚠️ **Monitor**: Current estimated cost is reasonable
- ⚠️ **Risk**: If retention is 90+ days + high volume → cost could spike
- 💡 **POST-DEMO CLEANUP**: After demo, consider:
  - Drop to 30-day retention (if not needed for audit)
  - Archive old tables
  - Potential savings: 30-50% reduction

**Recommendation**: REVIEW ingestion and retention; plan cleanup after demo

---

### 3. Key Vault (Low Cost, Non-Negotiable)

**Current State**:
- SKU: Standard ($0.60 per operation)
- Estimated operations: ~5-50/month (low volume in dev)
- **Monthly Cost**: ~$3-30 (typically < $10)

**Analysis**:
- ✅ **Essential**: Secrets management required
- ✅ **Low Cost**: No optimization needed
- ✓ **Already Hardened**: Purge protection + RBAC enabled (S4-05)

**Recommendation**: KEEP as-is (no cost optimization needed)

---

### 4. Public IP Addresses (Low Cost, Reducible)

**Current State**:
- Typically 2-3 public IPs (AKS ingress, management, potential DNS)
- Cost: ~$2.92 each/month = ~$6-9/month

**Analysis**:
- ⚠️ **Optional**: If Azure Firewall or load balancer can share IPs
- ✅ **Likely Minimal**: Dev environment probably only needs 1-2 public IPs
- 💡 **Opportunity**: Review allocation; unused IPs = dead cost

**Recommendation**: Audit public IP usage; deallocate unused IPs (~$3/month savings)

---

### 5. AKS Cluster (Not Found in RG - VERIFY LOCATION)

**Current State**:
- Query returned empty for `rg-clopr2-katar711-gwc`
- ⚠️ **May be in different resource group** (rg-clopr2-katar711-fce or separate)

**Typical AKS Cost** (if running):
- 1x node (Standard_B2s): ~$40/month (compute) + ~$74/month (AKS management) = **~$114/month**
- 2x nodes: ~$225+/month
- 3x nodes: ~$340+/month

**POST-DEMO CONSIDERATION**:
- ✅ If demo is short-lived → **Delete AKS after demo** (full cleanup)
- ⚠️ If AKS retained for testing → Plan monthly cost: ~$100-300+/month

**Recommendation**: VERIFY AKS location; plan destruction after demo (~50% cost reduction)

---

### 6. Traffic Manager (Optional, Low Cost)

**Current State**:
- Standard profile: ~$6/month (fixed fees only, no query charges in dev)
- Query cost: $0.57 per million queries (typically minimal in dev)

**Analysis**:
- ⚠️ **Optional**: Only needed if multi-region failover testing required
- 💡 **POST-DEMO**: If not testing multi-region → DELETE TM ($6/month savings)

**Recommendation**: DISABLE after demo (~$6/month savings)

---

### 7. Ancillary Services (Negligible)

- **NSGs**: $0 (included in subscription)
- **Virtual Networks**: $0 (included)
- **Bandwidth (Egress)**: ~$0-20/month (dev volume typically minimal)
- **Storage** (if used): ~$5-15/month (check if any disk snapshots retained)

**Recommendation**: MONITOR only; no immediate optimization

---

## Essential vs Optional Components

### ✅ ESSENTIAL (Keep Running)

| Component | Monthly Cost | Justification |
|-----------|-----------|--------------|
| Azure Arc (3x VMs) | ~$120 | Core production: Primary DB, Standby DB, App |
| Log Analytics (active monitoring) | ~$15-50 | Operational monitoring (can optimize later) |
| Key Vault | ~$5-10 | Secrets management (non-negotiable) |
| **Subtotal** | **~$140-180** | Production + Monitoring baseline |

### ⚠️ CONDITIONAL (Review After Demo)

| Component | Monthly Cost | Action |
|-----------|-----------|--------|
| AKS Cluster | ~$100-300 | **Destroy after demo** (major savings) |
| Traffic Manager | ~$6 | **Delete after demo** (not needed) |
| Log Analytics (post-demo) | ~$15-50 | **Reduce retention** (archive old data) |
| Public IPs (unused) | ~$3-9 | **Deallocate unused** (easy win) |
| **Subtotal** | **~$124-365** | Conditional - test/demo only |

---

## Cost-Saving Actions (Prioritized)

### Immediate (No Risk)
1. **Audit & Deallocate Unused Public IPs** 
   - **Savings**: ~$3-10/month
   - **Effort**: 15 minutes
   - **Risk**: Low (verify nothing using them first)

2. **Verify Public IP Allocation Method**
   - **If Static used where Dynamic would work**: Realloc to Dynamic
   - **Savings**: $0 currently (Static = $2.92/month, Dynamic = Free in PerGB2018 workspace)
   - **Note**: Actually, Azure charges for unused IPs regardless of type

3. **Review Log Analytics Retention & Ingestion**
   - **Current**: PerGB2018 @ ~2.30/GB
   - **Option A**: Cap ingestion (reduce details collected)
   - **Option B**: Archive old tables after 30 days
   - **Savings**: 20-40% = ~$5-20/month
   - **Effort**: 1-2 hours
   - **Risk**: May lose audit/debug data

### Post-Demo (Major Savings)
4. **Destroy AKS Cluster**
   - **Savings**: ~$100-300+/month
   - **Effort**: 30 minutes (azd down or manual delete)
   - **Risk**: Cannot re-test without redeployment
   - **Recommendation**: Do this first after demo

5. **Delete Traffic Manager Profile**
   - **Savings**: ~$6/month
   - **Effort**: 5 minutes
   - **Risk**: Low (recreate if needed for new demo)

6. **Archive Log Analytics Data**
   - **Reduce 90-day → 30-day retention** (if allowed)
   - **Savings**: 30-50% = ~$5-25/month
   - **Effort**: 1 hour
   - **Risk**: Lose historical data, but often acceptable for dev

### Long-Term (After Production Handoff)
7. **Evaluate VM Sizing**
   - Monitor pg-primary, pg-standby, app-onprem CPU/memory
   - If sustained < 30% utilization → downsize to Standard_B1s
   - **Savings**: ~$15/month per machine = ~$45/month total
   - **Effort**: 2 hours (monitoring + testing)
   - **Risk**: Medium (reboot required, potential throughput issues)

---

## Evidence Collected

**Resource Inventory** (S4-06-resource-inventory-*.txt):
- Azure Arc machines (3x)
- Log Analytics workspace configuration
- Key Vault SKU
- Public IP allocations
- Traffic Manager profiles (if any)

**Analysis Date**: 2026-03-13T16:35:00Z  
**Subscription**: Azure for Students (katar1@bts.lgk.lu)  
**Resource Group**: rg-clopr2-katar711-gwc

---

## Summary & Recommendations

### Current Baseline (All Services Running)
- **Monthly**: ~$260-475 USD
- **Annual**: ~$3,120-5,700 USD

### Post-Demo (Optimized for Cost)
- **Monthly**: ~$140-180 USD (AKS + TM deleted, logs archived)
- **Annual**: ~$1,680-2,160 USD
- **Savings**: ~60-70% reduction

### Recommended Action Plan
1. **Today (Post-Checkpoint)**: Deallocate unused public IPs (~$3-10/month savings)
2. **After Demo**: Delete AKS + TM + archive logs (~$110-330/month savings)
3. **Ongoing**: Monitor utilization; consider rightsizing VMs if headroom observed

---

**Cost Analysis Status**: INITIAL FINDINGS COMPLETE  
**Deliverables Remaining**: Evidence screenshots, documentation update, ClickUp comment  
**Timeline**: Continue during 17:00Z polling window

