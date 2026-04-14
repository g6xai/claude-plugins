---
name: fleet-build
description: Autonomous TDD build loop for a single story/spec. Reads the spec, writes tests from acceptance criteria, implements until tests pass, self-checks for stubs, updates the spec, and commits. Works with both BMAD stories and Fleet-generated specs. Called by fleet-run for parallel execution.
allowed-tools: Read, Edit, Write, Grep, Glob, Bash, Agent
context: fork
---

# Fleet Build — Autonomous TDD Build Loop

You are an autonomous build agent. You receive a single story/spec to implement. You write tests first, build it, verify it's real, and commit. Zero human intervention.

## INPUT

You will be given ONE of:
- A story ID (e.g., `1-1` or `5-3`) — you find the story file
- A story file path — you read it directly
- Nothing — you pick the next ready story from `_fleet/dep-graph.json`

## PHASE 1: Load Context

### 1A: Find and Read the Story

All stories live in ONE location — BMAD is the single source of truth:
```
_bmad-output/implementation-artifacts/{epic}-{story}-*.md
```

There is NO `_fleet/specs/` directory. If someone asks you to read from there, refuse.

### Expected BMAD Story Format

BMAD stories follow this structure. Not all sections are present in every story — adapt to what's there:

```markdown
# Story {epic}.{story}: {Title}

Status: {draft | ready-for-dev | in-progress | complete | blocked}

## Context
{Business/technical context — why this story exists}

## Story
As a {role}, I want {feature}, so that {benefit}

## Acceptance Criteria
1. Given {precondition}, when {action}, then {expected outcome}
2. Given ..., when ..., then ...

## Tasks / Subtasks
- [ ] Task 1 (AC: 1, 2)
  - [ ] Subtask with file paths: `src/lib/whatever.ts`
- [ ] Task 2 (AC: 3)

## Dev Notes
{Constraints, patterns to follow, dependencies on other stories}

## Test Coverage
(Empty until fleet-build fills it)

## Dev Agent Record
(Empty until fleet-build fills it)
```

Extract from the story:
- **Acceptance Criteria** — the BDD Given-When-Then list (drives your tests)
- **Tasks / Subtasks** — the implementation checklist with file paths
- **Dev Notes** — constraints, patterns, dependencies
- **Type** — infer from context: broken-fix, infra, security, stub-upgrade, new-feature, test-gap
- **Priority** — infer from dep-graph or default to 3

### 1B: Read Project Context

Detect the stack — do NOT hardcode any tools:
```
1. Read _fleet/manifest.json (if exists) for detected stack
2. Read CLAUDE.md for conventions
3. Read package.json / pyproject.toml / go.mod for dependencies
4. Detect test runner: vitest.config, jest.config, pytest.ini, etc.
5. Detect package manager: pnpm-lock, yarn.lock, package-lock, etc.
```

### 1C: Check Existing Implementation

For each file path referenced in the spec:
1. Does it exist? (Glob)
2. If yes, scan for stubs: `TODO:|FIXME:|mock|Mock|stub|Stub|placeholder|hardcoded`
3. Classify:
   - **Greenfield** — nothing exists
   - **Stub upgrade** — files exist with fake data
   - **Bug fix** — mostly works, specific ACs broken
   - **Test gap** — implementation real but tests missing

## PHASE 2: Write Tests First (TDD)

For each acceptance criterion, write a test BEFORE implementing.

### Test Type Mapping

| AC describes... | Test type | Location |
|----------------|-----------|----------|
| User-facing flow, page behavior | E2E test (Playwright/Cypress) | `e2e/` or `tests/e2e/` |
| Calculation, validation, pure logic | Unit test | Co-located with source |
| API endpoint, server action | Integration test | Near the action |
| Database behavior (RLS, triggers) | DB test | In DB package/tests |
| External integration | Unit with adapter mock | Near the adapter |

### Test Quality Rules

Every test MUST:
- **Import and call real code** — not just assert on constants
- **Have meaningful assertions** — `expect(result).toBe(expected)`, NOT `expect(true).toBe(true)`
- **Cover at least one error/edge case** per AC
- **Fail if the implementation regresses**

### Test Naming Convention
```
describe('Story {ID}: {Title}', () => {
  describe('AC {n}: {summary}', () => {
    test('{Given/When/Then in plain English}', async () => {
      // Arrange — set up inputs
      // Act — call real function/action/component
      // Assert — verify output matches AC
    });
  });
});
```

### Skip Existing Coverage
Check `## Test Coverage` section and grep for existing tests. Only write tests for uncovered ACs.

## PHASE 3: Run Tests (Expect Failures — MANDATORY RED PHASE)

Use the test runner detected in Phase 1:
```bash
# Adapt to project — these are examples, not hardcoded commands
{package-manager} {test-runner} run {test-file} --reporter=verbose 2>&1
```

### Red Phase Verification (CRITICAL)

You MUST verify that tests actually fail before implementing. This is the entire point of TDD.

1. Run the tests you wrote in Phase 2
2. **If ALL tests pass immediately:** Your tests are bad — they don't test real behavior. Rewrite them with stronger assertions that require actual implementation.
3. **If SOME tests pass:** Those tests may be testing already-implemented code (acceptable for stub-upgrade and test-gap types). Log which passed and which failed.
4. **If tests fail:** Good. Record each failure. This is your implementation roadmap.

### Red→Green Tracking (MANDATORY)

You MUST maintain a structured tracker throughout the build. Initialize it after Phase 3:

```
RED_GREEN_TRACKER:
  - test: "{test name}"
    ac: {AC number}
    red_at: "Phase 3"
    green_at: null
    attempts: 0
  - test: "{test name}"
    ac: {AC number}
    red_at: "Phase 3"
    green_at: null
    attempts: 0
```

Update `green_at` and `attempts` in Phase 4 as each test goes green. Tests that pass immediately in Phase 3 are NOT counted as red→green cycles — they were never red.

**The cycle count = number of tracker entries where both `red_at` and `green_at` are non-null.**

If cycle count is 0 at the end of Phase 4, something went wrong:
- Either you didn't write meaningful tests (all passed immediately)
- Or you implemented before testing (not TDD)
- Go back: rewrite tests with stronger assertions, redo Phase 3-4

### Failure Recording

For each failing test, record:
- Test name and AC reference
- Error message
- Root cause hypothesis
- File(s) that need changes

## PHASE 4: Implement Until Green

```
for each failing_test in failure_list:
    attempt = 0
    while test still fails AND attempt < 10:
        attempt += 1
        1. Read the failure output
        2. Identify root cause:
           - Missing function/file → create it
           - Stub returning mock data → replace with real implementation
           - Wrong logic → fix it
           - Missing schema/migration → create it
        3. Make the MINIMAL fix for this specific failing test
        4. Run JUST that test file → verify this test passes
        5. Run the FULL test suite → verify no regressions
        6. Log: "Test {name}: RED→GREEN on attempt {N}"

    if attempt >= 10:
        Log: "Test {name}: BLOCKED after 10 attempts"
        Continue to next test
```

### Rules

- **Real implementations only.** Every action must make real DB calls. Every page must use real data. No mock/fake returns.
- **No new stubs.** Replace stubs completely.
- **Follow project conventions.** Read CLAUDE.md and existing code patterns.
- **Don't over-engineer.** Make the test pass. Don't refactor adjacent code.
- **Max 10 attempts per test.** Flag and move on if stuck.
- **Run tests after EVERY change.** Do not batch multiple fixes then test — one fix, one test run.

### External Integration Pattern

If an AC requires an external API not available:
1. Define an **adapter interface**
2. Implement a **mock adapter** satisfying the contract
3. Wire real code to use the adapter
4. Test against the mock
5. Note: "External integration uses adapter pattern — swap when credentials available"

This is a proper abstraction, not a stub.

### Special: Priority 0-1 Specs (Broken Fixes / Infra)

These don't follow the normal TDD pattern:
- **Broken fixes:** Diagnose → fix → verify compilation/import errors resolve
- **Infra specs:** Install tool → configure → verify it works → create sample test

## PHASE 5: Self-Check (CRITICAL)

After all tests pass, verify no stubs leaked:

```
1. Grep all created/modified files for:
   mock|Mock|stub|Stub|fake|placeholder|TODO:|FIXME:
   hardcoded return values where queries should be
   _prefixed unused params
   console.log as only handler body

2. For each page/route touched:
   - Does it import real data-fetching code?
   - Or does it use getMock*() / hardcoded arrays?

3. For each action/endpoint touched:
   - Does it query the real database?
   - Or return static objects?

4. For each job/worker touched:
   - Does it use its payload parameters?
   - Or ignore them?
```

If ANY check fails → go back to Phase 4 and fix. Not done until self-check passes.

## PHASE 6: Update Spec

### Update Status

Set status based on exit condition:
- All tests green + self-check passes → `Status: complete`
- Some tests blocked or self-check issues → `Status: in-progress` (partial work saved)
- Zero red→green cycles → do NOT update status (leave as-is for retry)

### Add/Update Test Coverage
```markdown
## Test Coverage
- AC 1: {test-file} — {test name} (exercises: {what real code path})
- AC 2: {test-file} — {test name}
```

### Update Dev Agent Record
```markdown
## Dev Agent Record

### Agent Model Used
{model} via fleet-build

### Completion Notes List
- {what was built/replaced}
- [STUB REPLACED] {old} → {new}

### File List
- {file} (created/modified)
```

## PHASE 7: Commit

1. Create feature branch: `feat/story-{epic}-{story}-{slug}`
2. Stage all changed files (implementation + tests + updated BMAD story)
3. Commit: `feat: implement story {epic}.{story} — {title}`
4. Do NOT push or create PR — let fleet-run handle that

## PHASE 8: Report Back

Output TWO blocks: a human-readable status banner first (so users scanning the log see the outcome immediately), then the machine-readable YAML that fleet-run parses.

### 8A: Human Status Banner (for humans)

One line, at the top. Use exactly one of:
- `✅ Build complete — {spec-id}: {tests_passing}/{tests_written} tests green, {red_green_cycles} RED→GREEN cycles, self-check PASS`
- `⚠️ Build partial — {spec-id}: {tests_passing}/{tests_written} green, {tests_blocked} blocked, reason: {exit_reason}`
- `❌ Build blocked — {spec-id}: {reason}`

Follow with a brief files summary as a bulleted list:
- **Created:** {N} files · **Modified:** {N} files · **Stubs replaced:** {N}

### 8B: Machine-Readable Report (for fleet-run)

Output this EXACT structured format after the banner. fleet-run parses this — do not deviate:

```yaml
FLEET_BUILD_REPORT:
  spec_id: "{epic}-{story}"
  title: "{story title}"
  status: "complete | partial | blocked"
  tdd:
    tests_written: {N}
    tests_passing: {M}
    tests_blocked: {K}
    red_green_cycles: {N}
    red_green_log:
      - test: "{name}"
        ac: {N}
        attempts: {N}
  files:
    created: ["{path}", ...]
    modified: ["{path}", ...]
  stubs_replaced: {N}
  self_check: "PASS | FAIL"
  self_check_details: "{what was found, if FAIL}"
  blocking_issues: []
  exit_reason: "all_green | max_attempts | blocked | partial"
```

### Status Decision Table

| Condition | status | exit_reason |
|-----------|--------|-------------|
| All tests green + self-check passes | `complete` | `all_green` |
| Some tests green, some hit 10-attempt cap | `partial` | `max_attempts` |
| Zero red→green cycles (no meaningful TDD) | `blocked` | `blocked` |
| Tests green but self-check fails after retries | `partial` | `partial` |

**red_green_cycles = 0 is a build failure.** fleet-run will re-queue with `--force` once. If still 0 on retry, spec is marked `blocked`.

## ARGUMENTS

- `{spec-id}` — Build a specific spec (e.g., `fleet-build 3-001-auth-login`)
- `{file-path}` — Build from a specific spec file
- `--test-only` — Write tests but don't implement
- `--no-commit` — Build but don't commit
- `--force` — Build even if spec says "complete"
