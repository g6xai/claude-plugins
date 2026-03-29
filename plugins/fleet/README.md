# Fleet

**Software Engineering Operations Platform for Claude Code**

Fleet bootstraps any repository — greenfield or brownfield — for fully autonomous, process-compliant development. One plugin, works everywhere.

## Install

See the [parent repo README](../../README.md) for install instructions.

## What Fleet Does

- **Greenfield repos:** Detects BMAD, guides you through product brief → PRD → architecture → epics/stories
- **Brownfield repos:** Discovers tech stack, audits what's real vs stub, generates specs from gaps
- **Both:** Sets up test infrastructure, CI gates, process enforcement hooks, then runs parallel TDD agents
- **Always:** Syncs to Linear (tasks) and Notion (docs) with repo as single source of truth

## Relationship to BMAD

Fleet works **alongside** BMAD — it does not install, modify, or bundle BMAD. BMAD is a separate upstream framework for product planning (analysis → PRD → architecture → epics).

- **Greenfield:** Fleet detects if BMAD commands are available and guides the engineer through BMAD's planning phases. If BMAD isn't installed, Fleet tells you.
- **Brownfield:** Fleet generates specs in BMAD-compatible format so the same build/review loop works regardless of where specs came from.
- **Both use the same spec format**, so fleet-build, fleet-review, and fleet-sync work identically on BMAD stories and Fleet-generated specs.

## Skills

| Skill | Purpose |
|-------|---------|
| `fleet-init` | Universal entry point — detects repo state, routes to correct path |
| `fleet-discover` | Brownfield: map unknown repo (tech stack, structure, conventions) |
| `fleet-assess` | Brownfield: honest audit (classify complete vs stub vs missing) |
| `fleet-specgen` | Brownfield: generate BMAD-compatible specs from code gaps |
| `fleet-infra` | Set up test framework, CI pipeline, quality gate hooks |
| `fleet-sync` | Push repo state → Linear (issues) + Notion (docs) |
| `fleet-build` | TDD loop for one spec (write tests → implement → verify) |
| `fleet-review` | 5-check verification (spec compliance, stubs, quality, security, regression) |
| `fleet-run` | Full orchestrator — parallel builds, verify, merge, sync, loop |
| `fleet-doctor` | Project health check — build, tests, spec accuracy, sync drift |
| `fleet-guard` | Process enforcement hooks (spec-before-code, auto-format) |

## Agents

| Agent | Role |
|-------|------|
| `fleet-builder` | Autonomous TDD implementation (worktree-isolated) |
| `fleet-reviewer` | Read-only 5-check verification |
| `fleet-security` | OWASP security audit |
| `fleet-sync-agent` | Scheduled Linear/Notion synchronization |

## Principles

1. **Repo is truth.** Linear and Notion are mirrors. One-way sync only.
2. **Specs before code.** No implementation without acceptance criteria.
3. **TDD always.** Tests written before implementation.
4. **Honest audits.** Stubs are not implementations. Status must match reality.
5. **BMAD is upstream.** Fleet never modifies BMAD framework files.
