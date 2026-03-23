# ClickUp Task ID Convention — CLOPR2

**Document:** docs/09-process/clickup-task-id-convention.md
**Status:**   ACTIVE
**Date:**     2026-03-21
**Owner:**    KATAR711 | Team: BCLC24

---

## Purpose

Every non-trivial branch, PR, and commit in CLOPR2 must reference a ClickUp
task ID. This enables:

- automatic PR validation (CI enforces the convention — see `.github/workflows/clickup-validate.yml`)
- traceability from commit SHA back to sprint task
- structured sprint board updates (scripts use hardcoded IDs only when justified)

This convention applies to all work targeting the `main` branch.
It does NOT apply to typo fixes, whitespace-only changes, or `[skip ci]` commits.

---

## Finding Your Task ID

The task ID is the short alphanumeric code visible in the ClickUp task URL:

```
https://app.clickup.com/t/86c8u3pwy
                              ^^^^^^^^^  <- this is the task ID
```

Task IDs in this project are 9-character lowercase alphanumeric strings
(e.g. `86c8u3pwy`, `86c8xe9rj`). The convention works with any valid ClickUp
task ID length.

---

## Branch Naming

**Format:** `cu-{TASKID}/short-description`

Rules:
- prefix is always `cu-` (lowercase)
- task ID immediately follows with no separator
- a single `/` separates the task ID from the description
- description uses hyphens, no spaces, lowercase

```
# Valid
cu-86c8u3pwy/implement-ssh-precheck
cu-86c8xe9rj/gcp-portability-proof
cu-86c8wjpmu/dr-governance-ci-workflow
cu-86c8u3pwy/fix-wal-lag-gate-threshold

# Invalid
feature/implement-ssh-precheck          # missing task ID entirely
CU-86c8u3pwy/implement-ssh-precheck    # uppercase CU — regex won't match
cu86c8u3pwy/implement-ssh-precheck     # missing hyphen after cu
cu-86c8u3pwy-implement-ssh-precheck    # missing / separator
86c8u3pwy/implement-ssh-precheck       # missing cu- prefix
```

---

## PR Title Naming

**Format:** `[CU-{TASKID}] Brief description of change`

Rules:
- prefix `[CU-{TASKID}]` must be at the start of the title
- the task ID is uppercase `CU-` followed by the ClickUp ID
- description follows after a space

```
# Valid
[CU-86c8u3pwy] Implement ssh-precheck.sh for DR pre-flight gate
[CU-86c8xe9rj] GCP portability proof — Cloud Shell execution and evidence
[CU-86c8wjpmu] Add validate-registry.sh to ci-dr-governance workflow
[CU-86c8u3pwy] Fix WAL lag threshold in fullsite-failover.sh

# Invalid
Implement ssh-precheck.sh                         # no task ID
CU-86c8u3pwy: Implement ssh-precheck.sh           # missing square brackets
[86c8u3pwy] Implement ssh-precheck.sh             # missing CU- prefix
[CU-86c8u3pwy]: Implement ssh-precheck.sh         # colon after bracket
[cu-86c8u3pwy] Implement ssh-precheck.sh          # lowercase cu
```

The CI check (`clickup-validate.yml`) accepts the task ID from EITHER the PR
title OR the branch name. Both conventions are accepted; PR title takes
precedence in the check output.

---

## Commit Message Naming

**Format:** `type(scope): description [CU-{TASKID}]`

Commit messages must reference the task ID when the commit is part of a tracked
sprint task. The `[CU-{TASKID}]` token appears at the end of the subject line.

### Commit types

| Type       | Use for |
|------------|---------|
| `feat`     | New functionality |
| `fix`      | Bug or defect correction |
| `chore`    | Maintenance, dependency updates, config |
| `docs`     | Documentation only |
| `ci`       | CI workflow changes |
| `refactor` | Code restructuring without behaviour change |
| `test`     | Test additions or changes |

### Commit scopes

| Scope         | Use for |
|---------------|---------|
| `dr`          | DR scripts and runbooks |
| `terraform`   | Terraform environments or modules |
| `ansible`     | Ansible playbooks, roles, inventory |
| `ci`          | GitHub Actions workflows |
| `portability` | AWS/GCP proof environments |
| `governance`  | DR inventory, classify-vm, validate-registry |
| `process`     | Project process documents |
| `evidence`    | Evidence file additions |

```
# Valid
feat(dr): add WAL lag gate to fullsite-failover.sh [CU-86c8u3pwy]
fix(terraform): correct dr-fce location to francecentral [CU-86c8xe9rj]
docs(evidence): add S5-02 onprem-failover evidence [CU-86c8u3pwy]
ci(governance): add validate-registry.sh to ci-dr-governance [CU-86c8wjpmu]
chore(process): add clickup task ID naming convention [CU-86c8wjpmu]
refactor(dr): replace ((count++)) with arithmetic substitution [CU-86c8u3pwy]

# Invalid
add ssh precheck                                    # no type, no task ID
feat: implement ssh-precheck [86c8u3pwy]            # missing CU- prefix
feat(dr): add WAL lag gate to fullsite-failover.sh  # no task ID at all
```

### Commits that do NOT require a task ID

```
chore: fix typo in comment
docs: fix markdown formatting
Merge branch 'cu-86c8u3pwy/implement-ssh-precheck' into main  # merge commit — auto-generated
chore: auto sprint summary 20260321 [skip ci]                  # automated commit
```

---

## Summary Table

| Artifact      | Format                                  | Where task ID appears        |
|---------------|-----------------------------------------|------------------------------|
| Branch name   | `cu-{TASKID}/description`               | prefix, before `/`           |
| PR title      | `[CU-{TASKID}] Description`             | prefix, inside `[CU-...]`    |
| Commit message| `type(scope): description [CU-{TASKID}]`| suffix, inside `[CU-...]`    |

---

## CI Enforcement

The workflow `.github/workflows/clickup-validate.yml` runs on every PR
targeting `main` and fails if neither the PR title nor the branch name contains
a valid task ID reference.

The check is:
1. PR title matches `\[CU-[A-Za-z0-9]+\]`  — passes
2. Branch name matches `^cu-[A-Za-z0-9]+/` — passes (fallback)
3. Neither matches — fails with guidance

The check makes **no API calls** to ClickUp. It validates format only — it
does not verify that the task ID exists in ClickUp. A typo in the ID will
pass the format check but produce a 404 when API-based automation (future
Phase 2) attempts to update the task.

---

## Exemptions

The following branch names are permanently exempt from the task ID requirement:

| Branch pattern | Reason |
|----------------|--------|
| `main`         | primary branch — no PR from main to main |
| `hotfix/*`     | emergency fixes — add task ID as soon as practicable |
| `chore/ci-*`   | CI infrastructure maintenance may precede task creation |

To exempt a branch temporarily, add `[skip-cu]` anywhere in the PR title.
The validation workflow recognises this token and exits 0 with a skip notice.
Use sparingly and document the reason in the PR description.
