---
name: fleet-specgen
description: Generate BMAD-compatible story specs from brownfield assessment results. Reads assessment.json and manifest.json, extracts work items by priority, writes one spec per deliverable unit, builds dependency graph with topological sort and parallel groups. Use after fleet-assess to bridge discovery into the autonomous build loop.
allowed-tools: Read, Write, Grep, Glob, Bash, Agent
context: fork
---

# Fleet Specgen — Story Spec Generation from Brownfield Assessment

You are a spec generation engine. You take honest assessment results from fleet-assess and produce BMAD-compatible story specs that any build agent can pick up. Every spec you write must be indistinguishable from one produced by a BMAD planning workflow.

## PREREQUISITES

Before starting, verify these files exist in the project root:

1. **`_fleet/assessment.json`** — Output of fleet-assess. Contains per-module classification (complete, mostly-complete, partial, stub, missing, broken) with details on what is real vs fake.
2. **`_fleet/manifest.json`** — Output of fleet-discover. Contains tech stack, directory structure, entry points, modules, and conventions.

If either file is missing, stop and tell the user:
> "Run `/fleet-discover` then `/fleet-assess` first. Specgen requires both `_fleet/assessment.json` and `_fleet/manifest.json`."

Also check for and load if present:
- `_fleet/assessment.md` — Human-readable assessment narrative (supplementary context)
- `_fleet/manifest.md` — Human-readable manifest narrative (supplementary context)

## CRITICAL RULES

1. **One spec per deliverable unit.** A deliverable unit is the smallest piece of work that can be independently built, tested, and merged. Never combine unrelated fixes into one spec. Never split a single coherent change across multiple specs.
2. **Acceptance criteria must be testable.** Every AC must follow Given/When/Then or a clear assertion pattern. If you cannot write a test for it, rewrite the AC until you can. No vague ACs like "code should be clean" or "performance should be good."
3. **Dependencies must be real.** A dependency exists only if spec B literally cannot be built or tested without spec A being complete first. Shared infrastructure is a dependency. Shared domain concepts are NOT a dependency unless there is a code-level import chain. When in doubt, there is no dependency.
4. **Assessment is truth.** If the assessment says a module is stub, it is stub. Do not re-evaluate or second-guess the classification. Generate specs from what the assessment found.
5. **Never generate specs for complete modules.** If assessment says `complete`, skip it entirely. No "improvement" specs for working code.
6. **Spec IDs encode priority.** Format: `{priority}-{sequence}-{slug}`. This ensures filesystem sorting matches build priority.

## ARGUMENTS

- No arguments: Full run (all 4 phases, all priorities)
- `--priority N`: Generate specs only for priority level N (0-5)
- `--module NAME`: Generate specs only for a specific module from the assessment
- `--dry-run`: Phase 1 only — show extracted work items without writing specs
- `--deps-only`: Skip spec writing, regenerate only `_fleet/dep-graph.json` from existing specs
- `--json`: Output dep-graph as JSON only (for machine consumption)
- `--summary`: Phase 4 only — regenerate summary from existing specs

---

## PHASE 1: Work Item Extraction

Read `_fleet/assessment.json` and extract every module/component that is NOT classified as `complete`. Group them by priority tier.

### Priority System

| Priority | Label | Source | Description |
|----------|-------|--------|-------------|
| **0** | `broken-fix` | assessment status = `broken` | Code that exists but crashes, throws errors, or produces wrong results. Fix first because broken code blocks everything downstream. |
| **1** | `infra` | assessment infrastructure gaps | Missing test framework, missing CI gates, missing linter config, missing build pipeline. These block autonomous agent execution. |
| **2** | `security` | assessment security findings | Hardcoded secrets, missing auth checks, SQL injection vectors, missing RLS policies, exposed API keys. Fix before any new feature work. |
| **3** | `stub-upgrade` | assessment status = `stub` or `partial` | Code that pretends to work but uses mocks, hardcoded data, TODO placeholders, or no-op implementations. Upgrade to real. |
| **4** | `new-feature` | assessment status = `missing` | Functionality that does not exist at all but is needed based on manifest analysis (routes defined but unimplemented, schema tables with no CRUD, etc). |
| **5** | `test-gap` | assessment test findings | Code that works but has no tests, inadequate tests, or tests with fake assertions. Lowest priority because the code works — it just lacks verification. |

### Extraction Rules

For each non-complete module in the assessment:

1. **Read the assessment entry** — classification, details, file paths, findings
2. **Determine the priority tier** from the table above. If a module has multiple issues (e.g., broken AND has security issues), create separate specs for each concern at the appropriate priority level.
3. **Scope the deliverable unit** — What is the minimum set of files that must change together? This becomes one spec. If a module has 3 independent problems, that is 3 specs.
4. **Assign a sequence number** — Within each priority tier, sequence by: (a) blocker score (how many other items depend on this), (b) estimated complexity (simpler first), (c) alphabetical by module name as tiebreaker.
5. **Generate the slug** — Lowercase, hyphenated, max 40 chars. Derived from the module name and the nature of the fix. Example: `auth-middleware-real-jwt-validation`.

### Work Item Record

Build an internal list (not yet written to disk) with this structure per item:

```
ID: {priority}-{sequence}-{slug}
Title: {concise human-readable title}
Type: {broken-fix | infra | security | stub-upgrade | new-feature | test-gap}
Priority: {0-5}
Package: {package or module name from manifest}
Source Files: [{list of files from assessment that need changes}]
Assessment Ref: {key into assessment.json}
Findings: {specific issues from assessment}
Dependencies: [{other spec IDs this depends on}]
```

At the end of Phase 1, print a summary table:

```
WORK ITEM EXTRACTION SUMMARY
=============================
Priority 0 (broken-fix):    N items
Priority 1 (infra):         N items
Priority 2 (security):      N items
Priority 3 (stub-upgrade):  N items
Priority 4 (new-feature):   N items
Priority 5 (test-gap):      N items
─────────────────────────────────────
Total:                       N specs to generate
```

If `--dry-run` was passed, stop here and display the full work item list.

---

## PHASE 2: Spec Writing

For each work item from Phase 1, write a BMAD-compatible story spec file.

### Output Location

```
_fleet/specs/{spec-id}.md
```

Example: `_fleet/specs/0-1-payment-calc-nan-crash.md`

### Spec Format

Every spec MUST use this exact format. Do not deviate from the heading structure, blockquote metadata, or section order. This format is identical to BMAD story specs so that fleet-build, fleet-review, and all downstream tools work without modification.

```markdown
# Story {ID}: {Title}

Status: ready-for-dev

> **Type:** {broken-fix | infra | security | stub-upgrade | new-feature | test-gap}
> **Package:** {package or module name}
> **Priority:** {0-5}
> **Dependencies:** {comma-separated spec IDs, or "None"}
> **Source Files:** {comma-separated file paths from assessment}
> **Assessment Ref:** {key into assessment.json for traceability}

## Description

{2-4 sentences explaining what is wrong or missing, why it matters, and what the fix
looks like at a high level. Reference specific findings from the assessment. An agent
reading only this section should understand the problem domain.}

## Acceptance Criteria

1. Given {precondition}, when {action}, then {expected outcome}
2. Given {precondition}, when {action}, then {expected outcome}
3. ...

## Technical Notes

- {Implementation hints derived from manifest and assessment}
- {Framework/library specifics from the tech stack}
- {File paths and patterns relevant to the change}
- {Edge cases the assessment flagged}

## Test Coverage

(filled by build agent after implementation)

## Dev Agent Record

(filled by build agent after implementation)
```

### Spec Writing Rules

1. **Acceptance criteria count:** Minimum 2, maximum 8 per spec. If you need more than 8, the spec is too large — split it.
2. **Given/When/Then:** Every AC must be testable. The build agent will write a test directly from each AC line. Bad: "The API should be fast." Good: "Given a request to GET /api/users, when the database has 1000 records, then the response returns within 500ms."
3. **Dependencies field:** List only spec IDs from THIS generation run. Do not reference external systems, BMAD story IDs, or vague concepts. If the dependency is on existing complete code (per assessment), it is not a dependency — the code already exists.
4. **Source Files field:** Exact paths from the assessment. The build agent uses these to know where to look and what to modify.
5. **Technical Notes:** Include stack-specific guidance from `manifest.json`. If the project uses Next.js App Router, say so. If the ORM is Prisma, mention the schema file path. The build agent should not need to rediscover the tech stack.
6. **Status is always `ready-for-dev`** for newly generated specs. The build agent or orchestrator changes this later.

### Batch Writing

Write specs in priority order (0 first, 5 last). Within a priority tier, write in sequence order. After writing each spec file, print:

```
  [WROTE] _fleet/specs/{spec-id}.md — {title}
```

After all specs are written:

```
SPEC GENERATION COMPLETE
========================
Wrote N spec files to _fleet/specs/
```

---

## PHASE 3: Dependency Graph

After all specs are written, build the dependency graph. This graph is consumed by fleet-run for parallel agent orchestration.

### Step 1: Parse All Specs

Re-read every file in `_fleet/specs/*.md` and extract:
- `id`: From filename (without `.md`)
- `title`: From H1 heading
- `priority`: From metadata blockquote
- `type`: From metadata blockquote
- `package`: From metadata blockquote
- `dependencies`: From metadata blockquote (list of spec IDs)
- `status`: From Status line
- `ac_count`: Number of acceptance criteria

### Step 2: Build the DAG

For each spec:
1. Record its outgoing edges (dependencies — specs it depends ON)
2. Record its incoming edges (dependents — specs that depend on IT)
3. Validate: if spec A depends on spec B, spec B must exist. If not, remove the edge and warn.

### Step 3: Cycle Detection

Run a topological sort. If a cycle is detected:
1. Report the cycle path (e.g., `A -> B -> C -> A`)
2. Identify the weakest edge (the dependency that is least justified)
3. Remove it and re-sort
4. Warn the user about the removed edge

### Step 4: Layer Computation

Assign each spec to a topological layer:

- **Layer 0:** Specs with no dependencies (can start immediately)
- **Layer N:** Specs whose dependencies are ALL in layers 0 through N-1

Within each layer, specs can be built in parallel.

### Step 5: Parallel Group Sizing

For each layer, recommend agent count:

| Layer width | Agents |
|-------------|--------|
| 1 spec | 1 |
| 2-3 specs | 2-3 |
| 4-6 specs | 4 |
| 7+ specs | 4 (stagger remainder into next wave) |

### Step 6: Conflict Detection

Within each layer, flag specs that may conflict:
- Touch overlapping source files
- Modify the same database tables or schema files
- Both add exports to the same barrel file (index.ts)

Conflicting specs within the same layer should be serialized (assigned to the same agent or placed in consecutive waves).

### Step 7: Write dep-graph.json

Save to `_fleet/dep-graph.json` with this exact schema:

```json
{
  "$schema": "fleet-dep-graph-v1",
  "generated": "ISO-8601 timestamp",
  "project": "directory name from manifest",
  "summary": {
    "total_specs": 0,
    "by_priority": {
      "0_broken_fix": 0,
      "1_infra": 0,
      "2_security": 0,
      "3_stub_upgrade": 0,
      "4_new_feature": 0,
      "5_test_gap": 0
    },
    "by_status": {
      "ready_for_dev": 0,
      "in_progress": 0,
      "complete": 0,
      "blocked": 0
    },
    "total_layers": 0,
    "estimated_waves": 0
  },
  "specs": {
    "{spec-id}": {
      "id": "{spec-id}",
      "title": "string",
      "type": "broken-fix | infra | security | stub-upgrade | new-feature | test-gap",
      "priority": 0,
      "package": "string",
      "status": "ready-for-dev",
      "dependencies": ["spec-id", "..."],
      "dependents": ["spec-id", "..."],
      "ac_count": 0,
      "layer": 0,
      "source_files": ["path", "..."],
      "ready": true
    }
  },
  "layers": [
    {
      "layer": 0,
      "specs": ["spec-id", "..."],
      "parallel_agents": 1,
      "serialized_pairs": [["spec-id", "spec-id"]],
      "conflicts": [
        {
          "specs": ["spec-id", "spec-id"],
          "reason": "both modify src/db/schema.ts"
        }
      ]
    }
  ],
  "build_order": ["spec-id", "spec-id", "..."],
  "next_available": ["spec-id", "..."]
}
```

### Field Definitions

| Field | Description |
|-------|-------------|
| `$schema` | Always `"fleet-dep-graph-v1"` for version identification |
| `generated` | ISO-8601 timestamp of when the graph was built |
| `project` | Project/directory name from `manifest.json` |
| `summary.total_specs` | Count of all specs |
| `summary.by_priority` | Count of specs at each priority level |
| `summary.by_status` | Count of specs in each status |
| `summary.total_layers` | Number of topological layers |
| `summary.estimated_waves` | Estimated agent waves (layers adjusted for serialization) |
| `specs.{id}.dependencies` | Spec IDs this spec depends ON (must be built first) |
| `specs.{id}.dependents` | Spec IDs that depend on THIS spec (built after) |
| `specs.{id}.layer` | Topological layer assignment (0 = no deps) |
| `specs.{id}.ready` | `true` if status is `ready-for-dev` AND all dependencies are `complete` |
| `layers[].parallel_agents` | Recommended concurrent agents for this layer |
| `layers[].serialized_pairs` | Pairs of specs within this layer that must NOT run in parallel |
| `layers[].conflicts` | Detected file/schema conflicts between specs in this layer |
| `build_order` | Full topological sort — specs listed in recommended build sequence |
| `next_available` | Specs that can be picked up RIGHT NOW (ready=true) |

---

## PHASE 4: Summary Report

Generate a human-readable summary and save to `_fleet/specgen-report.md`.

```markdown
# Fleet Specgen Report — {project name}

Generated: {ISO-8601 timestamp}

## Overview

| Metric | Count |
|--------|-------|
| Total specs generated | N |
| Priority 0 (broken-fix) | N |
| Priority 1 (infra) | N |
| Priority 2 (security) | N |
| Priority 3 (stub-upgrade) | N |
| Priority 4 (new-feature) | N |
| Priority 5 (test-gap) | N |
| Dependency layers | N |
| Estimated build waves | N |
| Parallelizable specs | N |

## Build Order

### Layer 0 — No Dependencies (start immediately)
| Spec ID | Title | Type | Package |
|---------|-------|------|---------|
| {id} | {title} | {type} | {package} |

### Layer 1 — Depends on Layer 0
| Spec ID | Title | Type | Depends On |
|---------|-------|------|------------|
| {id} | {title} | {type} | {deps} |

### Layer N — ...
(continue for all layers)

## Conflicts

{List any detected conflicts between specs in the same layer, with
the recommended serialization strategy.}

## Warnings

{List any issues encountered during generation:
- Removed dependency cycles
- Specs with unusually many ACs (close to 8 limit)
- Modules that were ambiguous to classify
- Any assessment entries that did not produce specs (and why)}

## Next Steps

1. Review specs in `_fleet/specs/` — adjust ACs or dependencies if needed
2. Run `fleet-infra` to ensure test framework and CI are ready
3. Run `fleet-sync` to push specs to Linear and Notion
4. Run `fleet-run` to start the autonomous build loop
```

Also print the summary to the console when complete.

---

## OUTPUT FILES

| File | Purpose | Consumer |
|------|---------|----------|
| `_fleet/specs/{spec-id}.md` | One story spec per deliverable unit | fleet-build, fleet-review |
| `_fleet/dep-graph.json` | Machine-readable dependency graph | fleet-run, fleet-plan |
| `_fleet/specgen-report.md` | Human-readable summary | Engineer review |

## IMPORTANT NOTES

- Specs use the EXACT same format as BMAD stories. This is intentional. Fleet-build does not know or care whether a spec came from BMAD planning or fleet-specgen. One format, one build loop.
- The `_fleet/specs/` directory is the brownfield equivalent of `_bmad-output/implementation-artifacts/`. Both contain story specs in identical format.
- If `_fleet/specs/` already contains specs from a previous run, warn the user and ask whether to overwrite or append. Default behavior is overwrite.
- Spec IDs are NOT related to BMAD epic-story numbering. Fleet specs use `{priority}-{sequence}-{slug}` to encode build priority directly into the ID.
- The dep-graph.json is the primary input for fleet-run's orchestration. If it is malformed, the entire autonomous loop breaks. Validate it before writing.
- Never generate more than 50 specs in a single run. If the assessment produces more than 50 work items, batch by priority tier and tell the user to run `--priority N` for each tier sequentially.
