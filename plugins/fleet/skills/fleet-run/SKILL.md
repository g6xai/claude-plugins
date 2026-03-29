---
name: fleet-run
description: The outer orchestrator. Runs the full Fleet pipeline from bootstrap through parallel autonomous builds with Linear/Notion sync after each wave. The "start and walk away" command. Chains fleet-init → fleet-infra → fleet-sync → parallel fleet-build → fleet-review → fleet-sync → loop.
allowed-tools: Read, Edit, Write, Grep, Glob, Bash, Agent
context: fork
---

# Fleet Run — Full Autonomous Orchestration

You drive the entire Fleet pipeline from current state to completion. You are the orchestrator that chains all Fleet skills together and loops until everything is done.

## THE PIPELINE

```
fleet-run
  │
  ├── PHASE 0: BOOTSTRAP (one-time)
  │     ├── fleet-init (if not bootstrapped)
  │     ├── fleet-infra (if test framework missing)
  │     └── fleet-sync (initial push to Linear/Notion)
  │
  ├── PHASE 1: SANITY CHECK
  │     ├── Build compiles?
  │     ├── Existing tests pass?
  │     └── At least one spec ready?
  │
  ├── PHASE 2: PLAN
  │     ├── Read dep-graph
  │     ├── Pick current layer
  │     ├── Assign specs to agents (cap at --max-agents)
  │     └── Detect conflicts (shared files → serialize)
  │
  ├── PHASE 3: BUILD (parallel agents)
  │     ├── Spawn fleet-build per spec (worktree isolation)
  │     └── Monitor progress
  │
  ├── PHASE 4: VERIFY
  │     ├── fleet-review on each built spec
  │     ├── Run full test suite
  │     └── Flag failures for retry
  │
  ├── PHASE 5: MERGE
  │     ├── Consolidate branches
  │     ├── Resolve conflicts
  │     └── Push if configured
  │
  ├── PHASE 6: SYNC
  │     └── fleet-sync (update Linear + Notion with wave results)
  │
  ├── PHASE 7: REPORT
  │     ├── Wave summary
  │     ├── Progress stats
  │     └── What's next
  │
  └── PHASE 8: LOOP
        ├── More specs? → back to PHASE 2
        ├── All done? → final report
        └── Blocked? → report blockers, stop
```

## PHASE 0: BOOTSTRAP

Check for existing Fleet artifacts:

| Artifact | Missing? | Action |
|----------|----------|--------|
| `_fleet/manifest.json` | Missing | Run fleet-discover |
| `_bmad-output/implementation-artifacts/*.md` | Missing | Cannot proceed — run BMAD planning workflow first |
| Test framework | Not configured | Run fleet-infra |
| `_fleet/assessment.json` | Missing | Run fleet-assess (includes BMAD reconciliation) |
| `_fleet/dep-graph.json` | Missing | Run fleet-specgen (updates BMAD stories + builds dep-graph) |
| `_fleet/sync-state.json` | Missing | Run fleet-sync (optional) |

If ALL exist and are fresh (<24 hours), skip bootstrap.
If `--force-bootstrap` passed, re-run everything.
If `--skip-bootstrap` passed, trust existing artifacts.

## PHASE 1: SANITY CHECK

Before building anything:

### 1A: Build Check
```bash
{package-manager} build 2>&1
# or: {package-manager} tsc --noEmit 2>&1
```
If build is broken → check for Priority 0 spec → build that first (single agent).
If no P0 spec exists → generate one on the fly and build it.

### 1B: Test Check
```bash
{package-manager} test 2>&1
```
Record baseline: {N} tests, {M} passing, {K} failing.
Failing tests are acceptable — they may be for unimplemented specs.

### 1C: Ready Specs Check

Find BMAD stories with `Status: ready-for-dev` whose dependencies are all `Status: complete`:

Read the dep-graph:
- `_fleet/dep-graph.json` must exist (run fleet-specgen if missing)
- The dep-graph references BMAD stories in `_bmad-output/implementation-artifacts/`

If no specs are ready:
- All complete? → **DONE** — run final report
- All blocked? → Report blockers, **STOP**
- Circular dependency? → Report, suggest manual split, **STOP**

## PHASE 2: PLAN

### 2A: Identify Current Wave

From the dep-graph, find the first layer with unbuilt specs.

### 2B: Select Specs for This Wave

Pick up to `--max-agents` specs (default: 3) from the current layer.

Prioritize:
1. Priority 0 (broken) → always first
2. Priority 1 (infra) → before feature work
3. Lower priority number → first
4. More dependents → first (unblocks the most work)

### 2C: Detect Conflicts

Within the wave, check for specs that would conflict:
- Specs touching the same files → SERIALIZE (build one, then the other)
- Specs modifying the same DB tables → SERIALIZE
- Specs in different packages → PARALLELIZE
- All others → PARALLELIZE

### 2D: Output Plan

```
FLEET RUN — Wave {N} Plan
===========================
Parallel group 1:
  Agent 1: {spec-id} — {title}
  Agent 2: {spec-id} — {title}
Serial (after group 1):
  Agent 3: {spec-id} — {title} (conflicts with Agent 1)

Estimated duration: ~{N} minutes
```

## PHASE 3: BUILD

For each spec in the wave:

```
Spawn Agent:
  Tool: Agent
  Subagent_type: fleet:fleet-builder
  Prompt: "Build BMAD story at {story-file-path}"
  Isolation: worktree
  Branch: feat/story-{epic}-{story}-{slug}
  Background: true (for parallel execution)
  Timeout: 30 minutes
```

IMPORTANT: Always use `subagent_type: fleet:fleet-builder` — never use a general-purpose agent with a custom prompt. The fleet-builder agent enforces TDD by requiring a BMAD story file with testable ACs.

For serial specs, wait for the conflicting spec to complete before spawning.

Monitor agent completion. Log:
- Agent started: {spec-id} at {time}
- Agent completed: {spec-id} — {pass/fail} at {time} ({duration})

## PHASE 4: VERIFY

For each completed spec:

1. **Validate TDD compliance:**
   - Parse the agent's report for `Red→Green cycles`
   - If cycles = 0 AND spec type is NOT `infra` or `broken-fix`:
     - Log warning: "Spec {id} had 0 red→green cycles — tests may not be meaningful"
     - Re-queue with `--force` flag for one retry
   - If cycles > 0: TDD was followed, proceed to review

2. **Run fleet-review:**
   ```
   Spawn Agent: fleet-review with spec ID
   ```

3. **Collect verdicts:**
   - Pass → mark for merge
   - Fail (attempt 1-2) → re-queue for next wave
   - Fail (attempt 3) → mark as `blocked`

4. **Run full test suite** on the merged result (Phase 5 does actual merge).

## PHASE 5: MERGE

For each passing spec:

1. Merge the spec's feature branch into working branch:
   ```bash
   git merge feat/fleet-{spec-id} --no-ff
   ```

2. If merge conflict:
   - Attempt auto-resolution
   - If fails → serialize: revert this merge, queue spec for next wave

3. After all merges, run full test suite:
   ```bash
   {package-manager} test 2>&1
   ```

4. If regression detected:
   - Identify which merge caused it (binary search if needed)
   - Revert that merge
   - Mark that spec for re-attempt

5. If all clean:
   - Commit merge
   - Push if `--push` flag set
   - Create PR if `--pr` flag set

## PHASE 6: SYNC

Run fleet-sync to update Linear and Notion:
```
Spawn Agent: fleet-sync
```

This updates:
- Linear issue statuses for completed/failed specs
- Notion story database rows
- Progress stats on Notion project page

## PHASE 7: REPORT

```
FLEET RUN — Wave {N} Complete
===============================
Built:    {list with pass/fail}
Passed:   {count} specs
Failed:   {count} (will retry: {count}, blocked: {count})
Merged:   {count} specs

Overall Progress:
  Complete:    {N}/{total} specs ({percent}%)
  In Progress: {N}
  Ready:       {N}
  Blocked:     {N}

Next wave: {spec list}
Remaining waves: ~{estimate}

Time: {wave duration}
```

Append to `_fleet/run-progress.md`.

## PHASE 8: LOOP

| Condition | Action |
|-----------|--------|
| More ready specs | → Back to PHASE 2 |
| All specs complete | → Run fleet-doctor, output final report, **DONE** |
| No ready specs + some remain | → Report blockers, **STOP** |
| Max waves reached (`--max-waves`) | → **PAUSED** |
| Catastrophic failure | → Save state, **STOP** |

### Final Report (when all specs complete)

```
╔══════════════════════════════════════════════════╗
║  FLEET RUN — COMPLETE                            ║
╠══════════════════════════════════════════════════╣
║  All {N} specs implemented and verified.         ║
║                                                  ║
║  Waves: {N}                                      ║
║  Total time: {duration}                          ║
║  Specs: {N} complete, {N} blocked                ║
║  Tests: {N} total, all passing                   ║
║                                                  ║
║  Linear: {N} issues updated                      ║
║  Notion: Project page updated                    ║
║                                                  ║
║  Run /fleet-doctor for a full health check.      ║
╚══════════════════════════════════════════════════╝
```

## ERROR RECOVERY

### Agent crash mid-build
- Detect by timeout or error response
- Mark spec as `in-progress`, log the error
- Continue with other agents, re-queue for next wave

### Merge conflict between specs
- Attempt auto-resolution
- If fails: serialize the conflicting specs
- Never force-resolve — let the retry handle it

### Test suite timeout
- Cap at 5 minutes per run
- If timeout: report slow tests, continue with available results

### Sync failure (Linear/Notion unavailable)
- Log the failure, continue building
- Re-attempt sync in next wave
- Never block builds on sync failures

### Catastrophic failure
- Save full state to `_fleet/run-progress.md`
- Output diagnostics
- **STOP** (do not loop endlessly)

## ARGUMENTS

- No arguments: Full pipeline (bootstrap if needed + build loop)
- `--bootstrap-only`: Only run init/discover/assess/specgen/infra/sync
- `--skip-bootstrap`: Trust existing artifacts
- `--max-agents N`: Cap parallel agents (default: 3)
- `--max-waves N`: Stop after N waves (default: unlimited)
- `--layer N`: Only build layer N of dep-graph
- `--spec {id}`: Build one specific spec
- `--dry-run`: Show plan without executing
- `--resume`: Continue from last wave (reads run-progress.md)
- `--no-sync`: Skip Linear/Notion sync
- `--push`: Push branches to remote after merge
- `--pr`: Create PRs for merged work
- `--force-bootstrap`: Re-run all bootstrap steps
