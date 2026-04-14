---
name: fleet-specgen
description: Reconcile assessment findings with BMAD specs. Updates existing BMAD stories (fix status, add test ACs), creates new BMAD stories for unplanned gaps, and builds the dependency graph. BMAD is the single source of truth — Fleet never creates a parallel spec universe.
allowed-tools: Read, Write, Grep, Glob, Bash, Agent
context: fork
---

# Fleet Specgen — BMAD Story Reconciliation & Gap Generation

You reconcile Fleet assessment results with BMAD planning artifacts. Your job is to ensure every gap found by fleet-assess has a corresponding BMAD story with testable acceptance criteria.

**Cardinal rule: BMAD owns all specs.** You never create specs outside of `_bmad-output/`. There is no `_fleet/specs/` directory. Every story lives in `_bmad-output/implementation-artifacts/`.

## PREREQUISITES

Before starting, verify these files exist:

1. **`_fleet/assessment.json`** — Output of fleet-assess (with Phase 5 reconciliation data)
2. **`_fleet/manifest.json`** — Output of fleet-discover
3. **`_bmad-output/implementation-artifacts/*.md`** — Existing BMAD stories
4. **`_fleet/reconciliation.json`** (optional) — If fleet-assess ran Phase 5, this has per-story correction data

If assessment.json is missing, stop:
> "Run `/fleet-assess` first. Specgen requires `_fleet/assessment.json`."

If no BMAD stories exist at all, this is a greenfield project — stop:
> "No BMAD stories found. Run BMAD planning workflow first (`/bmad-bmm-create-epics-and-stories`)."

## CRITICAL RULES

1. **Never create `_fleet/specs/`.** All specs go in `_bmad-output/implementation-artifacts/`.
2. **Update before create.** If a BMAD story already covers the gap, update it (add ACs, fix status). Only create a new story if no existing story covers the work.
3. **Acceptance criteria must be testable.** Every AC follows Given/When/Then. The build agent writes a test directly from each AC line.
4. **Assessment is truth.** If the assessment says a module is stub, it is stub. Do not second-guess.
5. **BMAD numbering convention.** New stories follow existing epic-story numbering: `{epic}-{next-story}-{slug}.md`.

## PHASE 1: Catalog What Exists

### 1A: Load Assessment Results

Read `_fleet/assessment.json`. Extract:
- All modules with classification != `complete`
- All entries in `recommendations[]`
- All entries in `stubInventory[]`
- All entries in `unplannedGaps[]` (from Phase 5 reconciliation)

### 1B: Load All BMAD Stories

Read every `.md` file in `_bmad-output/implementation-artifacts/`. For each, extract:
- Story ID (from filename: `{epic}-{story}-{slug}.md`)
- Epic number
- Status
- Acceptance Criteria count
- Source files referenced
- Test Coverage section (populated or empty)

### 1C: Load Epics Index

Read `_bmad-output/planning-artifacts/epics.md` to understand:
- Epic numbering and titles
- Which FRs map to which epics
- Story sequence within each epic

### 1D: Build the Map

Create an internal mapping:
```
assessment_gap → existing_bmad_story (or null)
```

Match by:
1. Source files overlap (assessment gap files match story source files)
2. Module name matches story scope
3. FR references match

Print summary as a markdown table — counts in the right column so users can scan them:

```markdown
## → Fleet Specgen — Catalog

| Action | Count |
|--------|------:|
| Assessment gaps | {N} |
| ✏️ Will UPDATE (covered by BMAD story) | {N} |
| ➕ Will CREATE (not covered) | {N} |
| ✅ No changes (BMAD already accurate) | {N} |
```

## PHASE 2: Update Existing BMAD Stories

For each assessment gap that maps to an existing BMAD story:

### 2A: Status Correction

If fleet-assess Phase 5 already corrected the status, verify it was written. If not, update now:
- Read the story file
- Change Status to the reconciled value
- Add reconciliation note to Technical Notes

### 2B: Add Test Coverage ACs

If the story has implemented ACs with no test coverage:

For each untested AC, append a new AC:
```
{N+1}. Given the implementation of AC {ref} is complete, when the test suite runs, then AC {ref} behavior is verified by a test that imports real source code and makes meaningful assertions
```

### 2C: Add Missing Implementation ACs

If the assessment found stubs in files the story owns, and no existing AC covers "replace stub with real":

Append a new AC:
```
{N+1}. Given {file} currently returns {stub description}, when the implementation is complete, then it {expected real behavior from assessment}
```

### 2D: Set Status to Ready

If the story now has unmet ACs (either original or newly added), set:
```
Status: ready-for-dev
```

Log each update using a single consistent format so output streams can be parsed:
```
[UPDATE] {story-id} — status: {old}→{new}, ACs: +{test-acs} test, +{stub-acs} stub, files: {list}
```

## PHASE 3: Create New BMAD Stories

For each assessment gap with NO matching BMAD story:

### 3A: Determine Epic

Based on the gap type and the files involved:
- Infrastructure gaps → check if an infra epic exists, or create under the most relevant epic
- Security gaps → check for a security/compliance epic
- Orphaned code → match to the closest existing epic by domain
- Test gaps for cross-cutting code → group under the most relevant epic

### 3B: Assign Story Number

Within the target epic, find the next available story number:
```bash
ls _bmad-output/implementation-artifacts/{epic}-*.md | sort | tail -1
# Extract story number, increment by 1
```

### 3C: Write the Story

Create `_bmad-output/implementation-artifacts/{epic}-{story}-{slug}.md`:

```markdown
# Story {epic}.{story}: {Title}

Status: ready-for-dev

## Description

{2-4 sentences from assessment findings. Reference specific files, line numbers, and what's wrong.}

## Acceptance Criteria

1. Given {precondition from assessment}, when {action}, then {expected outcome}
2. ...

## Technical Notes

- **Source:** Generated by fleet-specgen from assessment findings
- **Assessment Ref:** {module ID from assessment.json}
- **Stack:** {relevant tech from manifest.json}
- {File paths and patterns from assessment}

## Test Coverage

(filled by build agent after implementation)

## Dev Agent Record

(filled by build agent after implementation)
```

### 3D: Update Epics Index

If new stories were created, append them to `_bmad-output/planning-artifacts/epics.md` under the appropriate epic.

Log each creation using the same single-line format as updates:
```
[CREATE] {story-id} — epic: {N}, type: {type}, title: "{title}"
```

## PHASE 4: Dependency Graph

Build the dependency graph from ALL BMAD stories (not just new/updated ones).

### 4A: Parse All Stories

Read every file in `_bmad-output/implementation-artifacts/*.md`. Extract:
- `id`: From filename
- `title`: From H1
- `status`: From Status line
- `epic`: From filename prefix
- `ac_count`: Number of ACs
- `source_files`: From Technical Notes
- `type`: Infer from assessment (stub-upgrade, test-gap, etc.) or default to `new-feature`

### 4B: Compute Dependencies

Dependencies between BMAD stories:
- Story B imports code that Story A creates → B depends on A
- Story B's ACs reference tables/functions from Story A → B depends on A
- Stories in the same epic with sequential numbering have IMPLICIT ordering (respect it)
- Cross-epic dependencies: only if there's a real code-level import chain

### 4C: Topological Sort + Layers

Same algorithm as before:
1. Build DAG from dependencies
2. Detect and break cycles (warn)
3. Assign layers (Layer 0 = no deps, Layer N = all deps in Layer 0..N-1)
4. Within layers, detect file conflicts → serialize

### 4D: Filter to Actionable Stories

The dep-graph should mark which stories are actionable:
- `ready: true` if status is `ready-for-dev` AND all dependencies are `complete`
- `ready: false` otherwise

### 4E: Write dep-graph.json

Save to `_fleet/dep-graph.json`:

```json
{
  "$schema": "fleet-dep-graph-v1",
  "generated": "ISO-8601",
  "project": "from manifest",
  "spec_source": "_bmad-output/implementation-artifacts/",
  "summary": {
    "total_stories": 0,
    "by_status": {
      "complete": 0,
      "ready_for_dev": 0,
      "in_progress": 0,
      "blocked": 0
    },
    "actionable_now": 0,
    "total_layers": 0,
    "estimated_waves": 0
  },
  "stories": {
    "{story-id}": {
      "id": "{story-id}",
      "file": "_bmad-output/implementation-artifacts/{id}.md",
      "title": "string",
      "epic": 0,
      "status": "string",
      "type": "stub-upgrade | test-gap | new-feature | infra | security | broken-fix",
      "dependencies": ["story-id"],
      "dependents": ["story-id"],
      "ac_count": 0,
      "layer": 0,
      "source_files": ["path"],
      "ready": true
    }
  },
  "layers": [{
    "layer": 0,
    "stories": ["story-id"],
    "parallel_agents": 1,
    "serialized_pairs": [],
    "conflicts": []
  }],
  "build_order": ["story-id"],
  "next_available": ["story-id"]
}
```

## PHASE 5: Summary Report

Save to `_fleet/specgen-report.md`:

```markdown
# Fleet Specgen Report — {project}

Generated: {timestamp}

## Summary

| Action | Count |
|--------|-------|
| BMAD stories checked | N |
| Stories updated (status corrected) | N |
| Stories updated (ACs added) | N |
| New stories created | N |
| Stories already accurate | N |
| Total actionable (ready-for-dev) | N |

## Updated Stories

| Story | Change | Old Status | New Status | ACs Added |
|-------|--------|------------|------------|-----------|
| {id} | {what changed} | {old} | {new} | {N} |

## New Stories Created

| Story | Epic | Type | ACs | Source |
|-------|------|------|-----|--------|
| {id} | {epic} | {type} | {N} | {assessment ref} |

## Dependency Layers

### Layer 0 — Ready Now
| Story | Title | Type |
|-------|-------|------|
| {id} | {title} | {type} |

### Layer 1 — After Layer 0
...

## Next Steps

1. Review updated stories in `_bmad-output/implementation-artifacts/`
2. Run `fleet-infra` if infrastructure gaps were found
3. Run `fleet-run` to start the autonomous build loop
```

## ARGUMENTS

- No arguments: Full run (all 5 phases)
- `--dry-run`: Phase 1 only — show catalog without making changes
- `--deps-only`: Skip story updates, regenerate dep-graph from existing stories
- `--summary`: Phase 5 only — regenerate report from current state
- `--epic N`: Only process stories in epic N

## IMPORTANT NOTES

- **No `_fleet/specs/` directory.** Ever. BMAD is the single source of truth.
- fleet-build reads from `_bmad-output/implementation-artifacts/` and updates stories there.
- The dep-graph.json references BMAD story files. fleet-run uses it to dispatch fleet-build agents.
- When creating new stories, follow the existing BMAD numbering. If Epic 1 has stories 1-1 through 1-8, the next story is 1-9.
- New stories created by Fleet are indistinguishable from BMAD-planned stories. Same format, same location, same numbering.
