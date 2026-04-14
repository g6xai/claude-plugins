---
name: fleet-init
description: Universal entry point for Fleet. Detects if a repo is greenfield (empty), brownfield (has code, no specs), or has existing BMAD/Fleet artifacts. Routes to the correct bootstrap path. The only command an engineer needs to know. Use when starting Fleet in any new repo.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Agent
context: fork
---

# Fleet Init — Universal Bootstrap Entry Point

You are the gateway to Fleet. Your job is to detect the current state of the repository and route the engineer to the correct bootstrap path. You make zero assumptions — you detect everything empirically.

## OUTPUT FORMATTING CONVENTIONS

All Fleet skills follow these output rules so users can skim reports consistently:

- **Status banner first.** Every report opens with a one-line status: `✅ Fleet Init — {STATE} detected` (or `⚠️` / `❌`). Users should see outcome within the first 100ms of scrolling.
- **Status badges for every check.** Use `✅` (ok), `⚠️` (partial / needs attention), `❌` (missing / failed), `⏭️` (skipped / N/A) — never prose-only.
- **Progress between phases.** Emit `→ Phase {N}: {name}...` before each phase and `✓ Phase {N} complete — {key metric}` after. Never leave the user staring at silence for >10 seconds.
- **Tables for ≥3 items.** Any checklist of 3+ items becomes a markdown table with columns for `Item | Status | Detail`.
- **Next step explicit.** Every final report ends with a `## Next Step` block containing exactly one command to run next.

## PHASE 1: DETECT REPO STATE

Emit before starting: `→ Phase 1: Detecting repo state...`

Run these checks in order:

### 1A: Is this a git repo?
```bash
git rev-parse --is-inside-work-tree 2>/dev/null
```
If not, initialize: `git init`

### 1B: Check for Fleet artifacts
```
Glob: _fleet/manifest.json
Glob: _fleet/assessment.json
Glob: _fleet/specs/*.md
Glob: _fleet/dep-graph.json
```
If `_fleet/manifest.json` exists → **CONTINUE** path (Fleet was already bootstrapped)

### 1C: Check for BMAD artifacts
```
Glob: _bmad-output/planning-artifacts/prd.md
Glob: _bmad-output/planning-artifacts/architecture.md
Glob: _bmad-output/planning-artifacts/epics.md
Glob: _bmad-output/implementation-artifacts/*.md
Glob: _bmad/bmm/config.yaml
```
Classify BMAD state:
- Has prd.md + architecture.md + epics.md + implementation stories → **BMAD COMPLETE** (ready for build)
- Has prd.md but missing architecture or stories → **BMAD PARTIAL** (resume planning)
- Has `_bmad/` directory but no output → **BMAD INSTALLED** (start planning)
- No BMAD at all → check for code

### 1D: Check for existing code
```bash
# Count source files (exclude node_modules, .git, vendor, dist, build, __pycache__)
find . -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.rb" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/vendor/*" \
  -not -path "*/dist/*" -not -path "*/build/*" -not -path "*/__pycache__/*" | wc -l
```
- 0 source files → **GREENFIELD** (empty repo)
- 1+ source files without BMAD → **BROWNFIELD** (has code, no specs)

### 1E: Determine path

| State | Path |
|-------|------|
| Fleet artifacts exist | CONTINUE |
| BMAD complete (all planning + stories) | BMAD-READY |
| BMAD partial (some planning done) | BMAD-RESUME |
| BMAD installed (no output yet) | BMAD-START |
| Code exists, no BMAD, no Fleet | BROWNFIELD |
| Empty repo | GREENFIELD |

After determining the path, emit:
```
✓ Phase 1 complete — state: {STATE}, routing to: {PATH}
```

## PHASE 2: EXECUTE PATH

### PATH: GREENFIELD (empty repo)

**Goal:** Detect if BMAD is available and guide the engineer through planning. Fleet does NOT install or modify BMAD — BMAD is a separate upstream framework.

1. **Check if BMAD commands are available:**
   - Look for BMAD commands in the skill/command list (e.g., `/bmad-bmm-create-product-brief`)
   - If BMAD is installed (either as a plugin or via repo `.claude/commands/`), proceed to step 2
   - If BMAD is NOT available, inform the user:
     ```
     BMAD planning commands are not installed. Fleet needs BMAD for greenfield projects.
     Install BMAD first, then re-run /fleet-init.

     Without BMAD, you can still use Fleet on brownfield repos that already have code.
     ```

2. **Inform the engineer** using this markdown template (no ASCII box art — it breaks on narrow terminals and misaligns with varying font widths):
   ```markdown
   ## ✅ Fleet Init — Greenfield Bootstrap

   This is an empty repo. Fleet will guide you through the full product
   development lifecycle, one phase at a time.

   ### Roadmap

   | # | Phase | Command | Status |
   |---|-------|---------|--------|
   | 1 | Product Brief | `/bmad-bmm-create-product-brief` | ⏭️ pending |
   | 2 | PRD | `/bmad-bmm-create-prd` | ⏭️ pending |
   | 3 | Architecture | `/bmad-bmm-create-architecture` | ⏭️ pending |
   | 4 | Epics & Stories | `/bmad-bmm-create-epics-and-stories` | ⏭️ pending |
   | 5 | Readiness Check | `/bmad-bmm-check-implementation-readiness` | ⏭️ pending |
   | 6 | Infrastructure | `/fleet-infra` | ⏭️ pending |
   | 7 | Sync to PM tools | `/fleet-sync` | ⏭️ pending |
   | 8 | Autonomous Build | `/fleet-run` | ⏭️ pending |

   Each phase has an AI agent that will guide you through it interactively.

   ### Next Step

   → Run `/bmad-bmm-create-product-brief` to start Phase 1.
   ```

3. **Create output directories** (these are Fleet/BMAD output locations, NOT BMAD framework files):
   ```
   mkdir -p _bmad-output/planning-artifacts
   mkdir -p _bmad-output/implementation-artifacts
   ```
   These directories hold YOUR project's specs. They are NOT part of BMAD itself.

### PATH: BROWNFIELD (has code, no specs)

**Goal:** Discover, assess, generate specs, and prepare for building.

1. **Run fleet-discover** (via Agent tool):
   ```
   Spawn Agent: fleet-discover
   Wait for manifest.json
   ```

2. **Show discovery results** to the user (use markdown table, not ASCII headings):
   ```markdown
   ## ✅ Fleet — Brownfield Discovery Complete

   | Metric | Value |
   |--------|-------|
   | Tech stack | {from manifest} |
   | Source files | {count} |
   | Test files | {count} |
   | CI | {platform or "❌ none"} |

   → Proceeding to assessment...
   ```

3. **Run fleet-assess** (via Agent tool):
   ```
   Spawn Agent: fleet-assess
   Wait for assessment.json
   ```

4. **Show assessment results:**
   ```markdown
   ## ✅ Fleet — Assessment Complete

   | Classification | Count |
   |----------------|-------|
   | ✅ Complete | {count} |
   | ⚠️ Partial | {count} |
   | ⚠️ Stub | {count} |
   | ❌ Missing | {count} |
   | **Total modules** | **{count}** |

   - Test coverage: {percent}%
   - Security issues: {count} {badge: ✅ if 0, ⚠️ if low, ❌ if critical}

   → Generating specs for {count} work items...
   ```

5. **Run fleet-specgen** (via Agent tool):
   ```
   Spawn Agent: fleet-specgen
   Wait for specs + dep-graph
   ```

6. **Show spec generation results:**
   ```markdown
   ## ✅ Fleet — Specs Generated

   | Priority | Type | Count |
   |----------|------|-------|
   | P0 | Broken | {count} |
   | P1 | Infra | {count} |
   | P2 | Security | {count} |
   | P3 | Stub upgrades | {count} |
   | P4 | New features | {count} |
   | P5 | Test gaps | {count} |
   | **Total** | | **{count}** |

   Dependency layers: {count}
   ```

7. **Ask the user:** "Ready to set up infrastructure and start building? (Y/n)"

8. If yes → run fleet-infra → fleet-sync → fleet-run

### PATH: BMAD-READY (planning complete, ready to build)

1. **Verify implementation artifacts exist:**
   ```
   Count files in _bmad-output/implementation-artifacts/
   Check for status fields in story specs
   ```

2. **Output:**
   ```markdown
   ## ✅ Fleet — BMAD Planning Complete

   - **Stories found:** {count}
   - **Status breakdown:** {breakdown}

   ### Next Step
   → Ready to set up infrastructure and start building. Run `/fleet-infra`.
   ```

3. → fleet-infra → fleet-sync → fleet-run

### PATH: BMAD-RESUME (partial planning)

1. **Detect which phase is complete:**
   - Has product brief? → Phase 1 done
   - Has PRD? → Phase 2 done
   - Has architecture? → Phase 3 done
   - Has epics but no stories? → Need story generation
   - Has stories? → All planning done, go to BMAD-READY

2. **Guide to next step:**
   ```markdown
   ## ⚠️ Fleet — BMAD Planning In Progress

   | Phase | Status |
   |-------|--------|
   | Product Brief | ✅ Complete |
   | PRD | ✅ Complete |
   | Architecture | ❌ Not found |
   | Epics & Stories | ⏭️ Pending |

   ### Next Step
   → Run `/bmad-bmm-create-architecture` to continue planning.
   ```

### PATH: CONTINUE (Fleet already bootstrapped)

1. **Run fleet-doctor** (quick health check)
2. **Show status:**
   ```markdown
   ## ✅ Fleet — Resuming

   | Metric | Value |
   |--------|-------|
   | Specs complete | {complete}/{total} ({percent}%) |
   | Last wave | {date} |
   | Next stories ready | {count} |

   **Ready stories:** {list}

   → Resuming autonomous build...
   ```
3. → fleet-run --resume

## ARGUMENTS

- No arguments: Auto-detect and route
- `--greenfield`: Force greenfield path
- `--brownfield`: Force brownfield path
- `--status`: Show current state without executing anything
- `--reset`: Clear _fleet/ artifacts and start fresh
