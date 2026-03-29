# Fleet

**Software Engineering Operations Platform for Claude Code**

Fleet bootstraps any repository — greenfield or brownfield — for fully autonomous, process-compliant development. One plugin, works everywhere.

## Install

See the [parent repo README](../../README.md) for install instructions.

## Quick Start

```bash
cd /path/to/any-repo

# First time — detects repo state, routes to correct path:
/fleet-init

# Autonomous build loop:
/fleet-run

# Health check:
/fleet-doctor

# Sync to Linear + Notion:
/fleet-sync
```

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

## Developing Fleet

Fleet is a standard Claude Code plugin. You can iterate on it from any repo where it's installed.

**How it works:** When you add Fleet as a local plugin path, Claude Code reads directly from that directory. Any edits to skill/agent/command files in the Fleet repo take effect on the next Claude Code restart (or session).

**Workflow for iterating on Fleet from another repo:**

1. You're working in e.g. `/path/to/my-project`
2. You notice a Fleet skill needs tweaking
3. Edit the skill directly at `/Users/Shared/code/fleet/skills/fleet-whatever/SKILL.md`
4. Restart Claude Code (or start a new session) — changes take effect
5. `cd /Users/Shared/code/fleet && git add -A && git commit -m "fix: ..."` to persist

**Or tell Claude Code to do it:**
```
"Update the fleet-build skill to also check for Python stubs"
→ Claude edits /Users/Shared/code/fleet/skills/fleet-build/SKILL.md
→ Restart to pick up changes
```

**Per-project Fleet config** (optional):
Create `.claude/fleet.local.md` in any project for project-specific overrides:
```yaml
---
linear_team: "Engineering"
notion_parent_page: "abc123"
max_parallel_agents: 5
strict_mode: false
---
```

## Architecture

```
/fleet-init → detects repo state
    ├── GREENFIELD → guides through BMAD planning (BMAD must be installed separately)
    ├── BROWNFIELD → discover → assess → specgen
    └── RESUME → picks up where you left off
         ↓
/fleet-infra → test framework, CI, hooks
         ↓
/fleet-sync → Linear + Notion (repo → external, one-way)
         ↓
/fleet-run → autonomous loop:
    PLAN → BUILD (parallel worktrees) → VERIFY → MERGE → SYNC → LOOP
```

## Principles

1. **Repo is truth.** Linear and Notion are mirrors. One-way sync only.
2. **Specs before code.** No implementation without acceptance criteria.
3. **TDD always.** Tests written before implementation.
4. **Honest audits.** Stubs are not implementations. Status must match reality.
5. **BMAD is upstream.** Fleet never modifies BMAD framework files.
