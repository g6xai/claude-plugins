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

### 1B: Test Baseline (CRITICAL — used by fleet-review)
```bash
{package-manager} test 2>&1
```
Record baseline and save to `_fleet/test-baseline.json`:
```json
{
  "recorded_at": "ISO-8601",
  "git_sha": "{current HEAD}",
  "total": {N},
  "passing": {M},
  "failing": {K},
  "failing_tests": ["{test name 1}", "{test name 2}"]
}
```
This baseline is used by fleet-review CHECK 5 (Regression) to distinguish pre-existing failures from new regressions. Update it after every successful merge in Phase 5.

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

Determine which specs can run in parallel vs must be serialized:

**Algorithm:**
1. For each spec in the wave, collect its **file footprint**:
   - Read the spec's `## Tasks / Subtasks` section — extract every file path mentioned
   - Read the dep-graph entry's `source_files` array (if present)
   - Identify the package/app the spec lives in (e.g., `apps/web`, `packages/db`, `apps/worker`)
2. Compare footprints pairwise:
   - **Any shared file paths** → SERIALIZE
   - **Same DB migration directory** (e.g., both touch `packages/db/migrations/`) → SERIALIZE
   - **Same API route directory** (e.g., both add routes under `src/app/api/`) → SERIALIZE
   - **Different packages entirely** (e.g., one in `apps/web`, other in `packages/compensation`) → PARALLELIZE
   - **Same package but no file overlap** → PARALLELIZE (optimistic — merge will catch conflicts)

**Conflict detection is conservative.** When in doubt, serialize. A slow correct build beats a fast broken merge.

### 2D: Output Plan

Emit the plan as structured markdown. Keep it scannable — reviewers should see outcomes in <5 seconds. If more than 10 specs are ready, show top N by priority and summarize the rest as `{N-N} more specs in layer {layer}`.

```markdown
## → Fleet Run — Wave {N} Plan

**Layer {layer}** · {total_ready} specs ready · {parallel_count} parallel · {serial_count} serial
**Estimated duration:** ~{N} minutes

### Parallel Group 1
| Agent | Spec | Title | Priority |
|-------|------|-------|----------|
| 1 | `{spec-id}` | {title} | P{n} |
| 2 | `{spec-id}` | {title} | P{n} |

### Serial (after group 1)
| Agent | Spec | Title | Conflicts with |
|-------|------|-------|----------------|
| 3 | `{spec-id}` | {title} | Agent 1 |
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

1. **Parse the build report:**
   - Look for `FLEET_BUILD_REPORT:` in the agent's output
   - Extract `status`, `red_green_cycles`, `exit_reason`
   - If report is missing or unparseable → treat as `blocked`

2. **Validate TDD compliance:**
   - If `red_green_cycles` = 0 AND spec type is NOT `infra` or `broken-fix`:
     - Log warning: "Spec {id} had 0 red→green cycles — tests may not be meaningful"
     - If this is the first attempt → re-queue with `--force` flag for one retry
     - If this is a retry (already has `--force`) → mark as `blocked`
   - If `status` = `partial` → re-queue (counts as one attempt)
   - If `status` = `blocked` → mark as `blocked` immediately (no retry)
   - If `status` = `complete` AND `red_green_cycles` > 0 → proceed to review

3. **Run fleet-review:**
   - Spawn fleet-reviewer agent (NOT a general-purpose agent) with the spec ID
   - fleet-review runs its 5 checks against the spec's feature branch

4. **Collect verdicts:**
   - Pass → mark for merge
   - Fail (attempt 1-2) → re-queue for next wave with review failure notes
   - Fail (attempt 3) → mark as `blocked` with full failure history

5. **Retry budget:** Each spec gets a maximum of **3 total build+review attempts**. The counter includes both TDD retries and review failures. On attempt 3, any failure is terminal → `blocked`.

## PHASE 5: MERGE

Merge verified specs one at a time, testing after each merge. Order by dependency (upstream specs first).

### 5A: Sequential Merge with Validation

```
for each passing_spec in dependency_order:
    1. Record pre-merge test baseline:
       {package-manager} test 2>&1
       Save: baseline_pass_count, baseline_fail_count

    2. Merge the spec's feature branch:
       git merge feat/story-{epic}-{story}-{slug} --no-ff

    3. If merge conflict:
       - Do NOT attempt auto-resolution of content conflicts
       - Git auto-merges are fine (non-conflicting changes to same file)
       - For real conflicts: revert merge, re-queue spec for next wave
         (the spec will be rebuilt against the new main state)

    4. Run full test suite:
       {package-manager} test 2>&1

    5. Compare against baseline:
       - If new failures > 0 (tests that were passing before now fail):
         - Revert this merge: git reset --hard HEAD~1
         - Mark spec for re-attempt in next wave
         - Log: "Spec {id} caused {N} regressions, reverted"
       - If no new failures:
         - Merge is clean, continue to next spec

    6. If all clean after all merges:
       - Push if `--push` flag set
       - Create PR if `--pr` flag set
```

### 5B: Why Sequential (Not Batch)

Merging all at once then testing makes it impossible to identify which spec caused a regression. Sequential merge with test-after-each means:
- You know exactly which merge broke things
- You can revert surgically
- Clean specs aren't held back by a broken one

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

Every wave report opens with a single-line status banner so the outcome is visible at a glance, followed by structured tables. Never dump wave results as prose.

```markdown
## {✅ | ⚠️ | ❌} Wave {N} Complete — {passed}/{total} passed ({success_pct}%) in {duration}

### Wave Results
| Spec | Status | Cycles | Review | Merged |
|------|--------|--------|--------|--------|
| `{id}` | ✅ pass | {N} | ✅ pass | ✅ yes |
| `{id}` | ❌ fail | {N} | ❌ regression | ❌ retry |

- **Passed:** {count} · **Failed:** {count} (retry: {count}, blocked: {count}) · **Merged:** {count}

### Overall Progress
| Status | Count | % |
|--------|-------|---|
| ✅ Complete | {N}/{total} | {pct}% |
| 🔨 In Progress | {N} | {pct}% |
| ⏭️ Ready | {N} | {pct}% |
| ❌ Blocked | {N} | {pct}% |

### Next Wave
- **Specs queued:** {spec list}
- **Estimated remaining waves:** ~{estimate}

### Next Step
→ Looping to PHASE 2 to plan wave {N+1}…
```

Use `✅` when all specs passed, `⚠️` when some passed, `❌` when none passed. Pick one — don't emit multiple banners. Append the full markdown block to `_fleet/run-progress.md`.

## PHASE 8: LOOP

| Condition | Action |
|-----------|--------|
| More ready specs | → Back to PHASE 2 |
| All specs complete | → Run fleet-doctor, output final report, **DONE** |
| No ready specs + some remain | → Report blockers, **STOP** |
| Max waves reached (`--max-waves`) | → **PAUSED** |
| Catastrophic failure | → Save state, **STOP** |

### Final Report (when all specs complete)

Use plain markdown — ASCII box art fragments on narrow terminals and screen readers. The headline `✅` badge is what users look for.

```markdown
# ✅ Fleet Run — Complete

All **{N} specs** implemented and verified.

## Summary
| Metric | Value |
|--------|-------|
| Waves | {N} |
| Total time | {duration} |
| Specs complete | {N} |
| Specs blocked | {N} |
| Tests passing | {N}/{N} |
| Linear issues updated | {N} |
| Notion | Project page updated |

## Next Step
→ Run `/fleet-doctor` for a full health check.
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
