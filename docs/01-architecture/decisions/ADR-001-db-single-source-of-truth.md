# ADR-001: Database single source of truth

## Status
Superseded by ADR-004

## Context
Hybrid DR requires consistent data and clean failover.

## Decision
Use Azure Database for PostgreSQL (EU region) as the authoritative DB for both on-prem and Azure compute.

## Rationale
Minimizes synchronization risk; enables fast failover.

## Consequences
Requires secure hybrid connectivity and strict network rules.

