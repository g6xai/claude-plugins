---
name: fleet-sync
description: Synchronize repository state to Linear and Notion. Creates/updates Linear projects, milestones, and issues from story specs. Creates/updates Notion project pages, PRD, architecture docs, and story database. Repo is always the source of truth — sync is one-way (repo → external).
allowed-tools: Read, Grep, Glob, Bash, Agent
context: fork
---

# Fleet Sync — Linear + Notion Synchronization

You project the repository's current state into Linear (task management) and Notion (documentation). The repo is ALWAYS the source of truth. This sync is ONE-WAY: repo → external tools. If someone edits a Linear issue or Notion page, the next sync overwrites it from repo.

## PREREQUISITES

At least one of:
- `_bmad-output/implementation-artifacts/*.md` (BMAD stories)
- `_fleet/specs/*.md` (Fleet-generated specs)
- `_fleet/dep-graph.json` or parseable dependency info in specs

Also needs:
- Linear MCP tools available (mcp__claude_ai_Linear__*)
- Notion MCP tools available (mcp__claude_ai_Notion__*)

If MCP tools are not available, report what WOULD be synced and skip the actual sync.

## PHASE 1: Gather Repo State

### 1A: Collect All Specs

Find all story/spec files:
```
BMAD: _bmad-output/implementation-artifacts/*.md
Fleet: _fleet/specs/*.md
```

For each, extract:
- ID (from filename)
- Title (from H1 heading)
- Status (from Status: line)
- Epic/milestone (from epic number or Priority group)
- Acceptance criteria (full text)
- Dependencies (from Dependencies: line)
- Type (from Type: line, or infer from BMAD format)
- Priority

### 1B: Collect Planning Artifacts

Check for:
- `_bmad-output/planning-artifacts/prd.md` — Product Requirements Document
- `_bmad-output/planning-artifacts/architecture.md` — Architecture doc
- `_bmad-output/planning-artifacts/epics.md` — Epic overview
- `_bmad-output/planning-artifacts/product-brief-*.md` — Product brief
- `_fleet/assessment.md` — Brownfield assessment report
- `_fleet/manifest.md` — Repo discovery report

### 1C: Compute Summary Stats

```json
{
  "total_specs": 0,
  "by_status": { "complete": 0, "in-progress": 0, "ready-for-dev": 0, "blocked": 0 },
  "by_epic": { "1": { "total": 0, "complete": 0 } },
  "completion_rate": 0.0
}
```

## PHASE 2: Sync to Linear

### 2A: Find or Create Project

1. Search Linear for a project matching the repo name:
   ```
   Use: mcp__claude_ai_Linear__list_projects
   Match by name or slug
   ```
2. If not found, create it:
   ```
   Use: mcp__claude_ai_Linear__save_project
   name: {repo name from CLAUDE.md or package.json}
   description: {from PRD executive summary or README}
   ```
3. Store the project ID in `_fleet/sync-state.json` for future runs

### 2B: Find or Create Team

Linear requires a team for issues. Check for existing teams:
```
Use: mcp__claude_ai_Linear__list_teams
```
Use the first team found, or ask the user which team to use.

### 2C: Create/Update Milestones (Epics)

For each epic found in specs:
1. Check if milestone exists (by name match):
   ```
   Use: mcp__claude_ai_Linear__list_milestones with project filter
   ```
2. Create or update:
   ```
   Use: mcp__claude_ai_Linear__save_milestone
   name: "Epic {N}: {Title}"
   project: {project ID}
   description: {epic description from epics.md}
   ```

### 2D: Create/Update Labels

Create labels for spec types and priorities:
```
Use: mcp__claude_ai_Linear__create_issue_label
Labels: fleet:broken-fix, fleet:infra, fleet:security, fleet:stub-upgrade,
        fleet:new-feature, fleet:test-gap, fleet:p0, fleet:p1, fleet:p2,
        fleet:p3, fleet:p4, fleet:p5
```

### 2E: Create/Update Issues (Stories)

For each spec/story:

1. Check if issue already exists:
   - Search by title match, or
   - Check `_fleet/sync-state.json` for stored Linear ID mapping

2. Map status:
   | Repo Status | Linear State |
   |-------------|-------------|
   | ready-for-dev | Backlog |
   | in-progress | In Progress |
   | complete | Done |
   | blocked | Backlog (with blocked label) |
   | needs-review | In Review |

3. Create or update:
   ```
   Use: mcp__claude_ai_Linear__save_issue
   title: "Story {ID}: {Title}"
   team: {team ID}
   project: {project ID}
   milestone: {epic milestone ID}
   state: {mapped state}
   priority: {mapped priority}
   labels: [{type label}, {priority label}]
   description: {acceptance criteria as markdown}
   ```

4. Set dependency relations:
   ```
   blockedBy: [Linear IDs of dependency specs]
   blocks: [Linear IDs of dependent specs]
   ```

5. Link to repo spec file:
   ```
   links: [{ url: "{repo-url}/blob/main/{spec-path}", title: "Spec file" }]
   ```

### 2F: Detect Orphaned Issues

Find Linear issues in the project that don't match any repo spec:
- List all issues in project
- Compare against repo specs
- For orphans: add comment "This issue is not tracked in the repo. It may have been removed or renamed."

### 2G: Store Sync State

Save to `_fleet/sync-state.json`:
```json
{
  "last_sync": "ISO-8601",
  "linear": {
    "project_id": "...",
    "team_id": "...",
    "milestone_ids": { "epic-1": "...", "epic-2": "..." },
    "issue_ids": { "1-1": "LIN-123", "1-2": "LIN-124" }
  },
  "notion": {
    "project_page_id": "...",
    "prd_page_id": "...",
    "architecture_page_id": "...",
    "story_database_id": "...",
    "story_data_source_id": "..."
  }
}
```

## PHASE 3: Sync to Notion

### 3A: Find or Create Project Page

1. Search Notion for existing project page:
   ```
   Use: mcp__claude_ai_Notion__notion-search
   query: {repo name}
   ```
2. If not found, create a workspace-level page:
   ```
   Use: mcp__claude_ai_Notion__notion-create-pages
   properties: { "title": "{Repo Name} — Fleet Project" }
   content: "# {Repo Name}\n\nManaged by Fleet. Repo is the source of truth."
   ```

### 3B: Create/Update PRD Page

If PRD exists (`_bmad-output/planning-artifacts/prd.md`):
1. Read the full PRD content
2. Create or update a sub-page under the project page:
   ```
   Use: mcp__claude_ai_Notion__notion-create-pages
   parent: { page_id: {project page ID} }
   properties: { "title": "Product Requirements Document" }
   content: {PRD content as Notion Markdown}
   ```

### 3C: Create/Update Architecture Page

Same pattern as PRD for `architecture.md`.

### 3D: Create Story Database

Create a Notion database to track all stories:
```
Use: mcp__claude_ai_Notion__notion-create-database
parent: { page_id: {project page ID} }
title: "Stories"
schema: CREATE TABLE (
  "Title" TITLE,
  "Status" SELECT('Ready':gray, 'In Progress':blue, 'Complete':green, 'Blocked':red),
  "Epic" SELECT({dynamic from epics}),
  "Priority" SELECT('P0 Critical':red, 'P1 Infra':orange, 'P2 Security':yellow, 'P3 Stub':blue, 'P4 New':green, 'P5 Tests':gray),
  "Type" SELECT('broken-fix':red, 'infra':orange, 'security':yellow, 'stub-upgrade':blue, 'new-feature':green, 'test-gap':gray),
  "Dependencies" RICH_TEXT,
  "Linear Issue" URL,
  "Spec File" URL
)
```

### 3E: Populate Story Database

For each spec/story, create a row:
```
Use: mcp__claude_ai_Notion__notion-create-pages
parent: { data_source_id: {story database data source ID} }
properties: {
  "Title": "Story {ID}: {Title}",
  "Status": "{mapped status}",
  "Epic": "Epic {N}",
  "Priority": "P{N} {label}",
  "Type": "{type}",
  "Dependencies": "{comma-separated dependency IDs}",
  "Linear Issue": "{Linear issue URL}",
  "Spec File": "{repo URL to spec file}"
}
content: {acceptance criteria + implementation notes}
```

### 3F: Create Views

Create useful views on the story database:

1. **Board View** (grouped by status):
   ```
   Use: mcp__claude_ai_Notion__notion-create-view
   type: board
   configure: GROUP BY "Status"
   ```

2. **Table View** (all stories sortable):
   ```
   type: table
   configure: SORT BY "Epic" ASC
   ```

3. **By Epic View**:
   ```
   type: table
   configure: GROUP BY "Epic"; SORT BY "Priority" ASC
   ```

### 3G: Update Project Page Summary

Update the project page with current stats:
```markdown
## Project Status
- Total stories: {N}
- Complete: {N} ({percent}%)
- In Progress: {N}
- Ready: {N}
- Blocked: {N}

Last synced: {ISO-8601}
```

## PHASE 4: Report

```
FLEET SYNC COMPLETE
====================
Linear:
  Project: {name} ({id})
  Milestones: {count} (epics)
  Issues: {created} created, {updated} updated, {orphaned} orphaned

Notion:
  Project page: {url}
  PRD: {synced/skipped}
  Architecture: {synced/skipped}
  Story database: {count} rows
  Views: board, table, by-epic

Sync state saved to: _fleet/sync-state.json
```

## INCREMENTAL SYNC

On subsequent runs, fleet-sync is incremental:
1. Read `_fleet/sync-state.json` for existing IDs
2. Only update changed specs (compare status, title, ACs)
3. Create new specs that don't have Linear/Notion entries
4. Flag removed specs as orphaned

## ARGUMENTS

- No arguments: Full sync (Linear + Notion)
- `--linear-only`: Only sync to Linear
- `--notion-only`: Only sync to Notion
- `--dry-run`: Show what would be synced without doing it
- `--force`: Re-sync everything (ignore sync-state.json)
- `--spec {id}`: Sync only one spec
