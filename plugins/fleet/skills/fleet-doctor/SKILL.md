---
name: fleet-doctor
description: Full project health check. Runs all audits, checks infrastructure, verifies spec completion against code, checks Linear/Notion sync drift, and produces a unified report. The one command to understand project state.
allowed-tools: Read, Grep, Glob, Bash, Agent
context: fork
---

# Fleet Doctor — Project Health Check

You run a comprehensive health check on the project and produce a unified report. This is the "what state is this repo in?" command.

## WHAT GETS CHECKED

1. **Build health** — Does the project compile/build?
2. **Test health** — Do tests pass? How many? Coverage?
3. **Spec accuracy** — Do spec statuses match actual code?
4. **Stub detection** — Are there hidden stubs in "complete" stories?
5. **Infrastructure** — Test framework, CI, hooks present?
6. **Sync drift** — Do Linear/Notion match repo state?
7. **Dependency health** — Are there blocked or circular dependencies?

## PHASE 1: Quick Checks (Parallel)

Run these simultaneously via subagents or sequential bash:

### 1A: Build Check
```bash
{package-manager} build 2>&1
# or: {package-manager} tsc --noEmit 2>&1
```
Result: PASS / FAIL (with error count)

### 1B: Lint Check
```bash
{package-manager} lint 2>&1
```
Result: PASS / FAIL (with warning/error counts)

### 1C: Test Check
```bash
{package-manager} test 2>&1
```
Result: {N} tests, {M} passing, {K} failing, {J} skipped

### 1D: Type Check (if TypeScript/typed language)
```bash
{package-manager} tsc --noEmit 2>&1
```
Result: PASS / FAIL (with error count)

## PHASE 2: Spec Accuracy Audit

For each spec/story with `Status: complete`:

1. Read the acceptance criteria
2. For each AC, check if corresponding test exists and passes
3. Grep implementation files for stub indicators:
   ```
   TODO:|FIXME:|mock|Mock|stub|Stub|placeholder|hardcoded
   ```
4. Classify honestly:
   - **Verified complete** — tests exist, pass, no stubs
   - **Likely complete** — implementation exists, no stubs, but missing tests
   - **Overstated** — marked complete but has stubs or failing tests
   - **Missing** — marked complete but no implementation found

Report mismatches.

## PHASE 3: Infrastructure Check

| Item | Check | Status |
|------|-------|--------|
| Test framework | Config file exists + `test` script in package.json | ✅/❌ |
| E2E framework | Playwright/Cypress config exists | ✅/❌/N/A |
| CI pipeline | `.github/workflows/` or equivalent exists | ✅/❌ |
| CI gates | Lint + typecheck + test in CI | ✅/partial/❌ |
| Fleet hooks | `.claude/settings.json` has Fleet hooks | ✅/❌ |
| CLAUDE.md | Project instructions exist | ✅/❌ |
| Fleet artifacts | `_fleet/` directory with manifest/assessment | ✅/❌/N/A |
| BMAD artifacts | `_bmad-output/` with planning docs | ✅/❌/N/A |

## PHASE 4: Sync Drift Check

If `_fleet/sync-state.json` exists:

### Linear Drift
1. Read sync-state for issue ID mappings
2. For each mapped spec, compare repo status vs Linear status
3. Report mismatches

### Notion Drift
1. Check if Notion pages exist (by stored IDs)
2. Compare story count in Notion DB vs repo specs
3. Report mismatches

If sync-state doesn't exist → report "Not synced. Run /fleet-sync."

## PHASE 5: Dependency Health

Read dep-graph (Fleet or compute from specs):
1. Count specs per status per layer
2. Detect circular dependencies
3. Identify bottleneck specs (most dependents, not yet complete)
4. Identify orphan specs (no dependencies, no dependents — possibly outdated)

## OUTPUT: Doctor Report

Save to `_fleet/doctor-report.md`:

```markdown
# Fleet Doctor Report — {date}

## Executive Summary
- **Build:** {PASS/FAIL}
- **Tests:** {N} passing, {M} failing
- **Specs:** {N} verified complete, {M} overstated, {K} ready
- **Infrastructure:** {N}/{M} checks passing
- **Sync:** {in sync / {N} drifts / not synced}

## Build & Quality
| Check | Result | Details |
|-------|--------|---------|
| Build | {PASS/FAIL} | {error count if fail} |
| Lint | {PASS/FAIL} | {N} warnings, {M} errors |
| Typecheck | {PASS/FAIL} | {N} errors |
| Tests | {N}/{M} passing | {failing test names} |

## Spec Accuracy
| Spec | Declared Status | Actual Status | Issue |
|------|----------------|---------------|-------|
{only show mismatches}

## Infrastructure
| Item | Status | Action Needed |
|------|--------|---------------|
{full infrastructure table}

## Sync Status
- Linear: {in sync / N drifts}
- Notion: {in sync / N drifts}
{drift details if any}

## Dependency Health
- Layers: {N}
- Ready to build: {N} specs
- Blocked: {N} specs
- Bottlenecks: {spec IDs that block the most work}
- Circular deps: {none / list}

## Recommended Actions
1. {prioritized list of what to fix/do next}
```

Also output the report to stdout for the user.

## ARGUMENTS

- No arguments: Full health check
- `--quick`: Skip spec accuracy audit (faster)
- `--specs-only`: Only check spec accuracy
- `--infra-only`: Only check infrastructure
- `--sync-only`: Only check sync drift
