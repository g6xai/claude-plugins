---
name: fleet-review
description: Verify a completed spec/story was actually implemented correctly. Checks spec compliance, stub contamination, code quality, security, and regression. The quality gate between "agent says done" and "actually done." Called by fleet-run after each build wave.
allowed-tools: Read, Grep, Glob, Bash, Agent
context: fork
---

# Fleet Review — Post-Build Verification

You verify that a completed spec was actually implemented correctly. You are the quality gate. You never trust self-reported status — you verify against code.

## INPUT

One or more spec IDs to verify (e.g., `fleet-review 3-001-auth-login 3-002-user-profile`).

If no IDs given, verify all specs with `Status: complete` that don't have a passing review in `_fleet/reviews/`.

## CHECK 1: Spec Compliance

For the spec being reviewed:

1. Read the acceptance criteria
2. For each AC:
   a. Find the test that covers this AC (from `## Test Coverage` section)
   b. Read the test file — does it import real code and make real assertions?
   c. Run the test — does it pass?
   d. Read the implementation — does the behavior match the AC's expected outcome?
3. Score: `{acs_verified} / {acs_total}`

**Failure criteria:** Any AC without a passing test with real assertions.

## CHECK 2: Stub Contamination

Grep ALL files listed in the spec's `## Dev Agent Record → File List`:

```
Patterns to detect:
  TODO:|FIXME:|HACK:|XXX:|PLACEHOLDER
  mock|Mock|MOCK (in non-test files)
  fake|Fake|stub|Stub|STUB
  placeholder|dummy|simulated
  hardcoded (in comments)
  Functions returning static arrays/objects (no DB call)
  Unused parameters: _param pattern (not in tests)
  console.log as only statement in handler
  throw new Error('Not implemented')
  pass (Python) as only function body
  Empty function bodies: { return; } or { }
```

**For stub-upgrade specs:** Verify the ORIGINAL stubs (from the assessment) are gone. Diff against `_fleet/assessment.json` module record.

**Failure criteria:** Any stub indicator in non-test implementation files.

## CHECK 3: Code Quality

1. Run linter on changed files (if linter configured):
   ```bash
   {linter} {changed-files} 2>&1
   ```
2. Run type checker on changed files (if typed language):
   ```bash
   {type-checker} --noEmit 2>&1
   ```
3. Check for:
   - Dead imports (imported but not used)
   - Circular imports
   - Files larger than 500 lines (suggest splitting)
   - Duplicated code blocks (>10 identical lines elsewhere)

**Failure criteria:** Lint errors or type errors in changed files.

## CHECK 4: Security

Quick security scan of changed files:

1. Hardcoded secrets: `sk-|AKIA|password\s*=\s*['"]|api_key\s*=\s*['"]`
2. SQL injection: raw string concatenation in queries
3. Missing auth checks: new API routes/endpoints without auth middleware
4. XSS vectors: `dangerouslySetInnerHTML` or `v-html` with user input
5. Exposed debug info: `console.log` of sensitive data, stack traces in responses

**Failure criteria:** Any security issue found.

## CHECK 5: Regression

Run the FULL test suite (not just this spec's tests):

```bash
{package-manager} test 2>&1
```

Compare against last known passing state. Did any previously passing test break?

**Failure criteria:** Any test that was passing before this spec's changes now fails.

## OUTPUT

Per-spec verdict saved to `_fleet/reviews/{spec-id}-review.json`:

```json
{
  "spec_id": "3-001-auth-login",
  "reviewed_at": "ISO-8601",
  "verdict": "pass | fail | partial",
  "checks": {
    "spec_compliance": {
      "pass": true,
      "acs_verified": 5,
      "acs_total": 5,
      "details": []
    },
    "stub_contamination": {
      "pass": true,
      "stubs_found": 0,
      "details": []
    },
    "code_quality": {
      "pass": true,
      "lint_errors": 0,
      "type_errors": 0,
      "details": []
    },
    "security": {
      "pass": true,
      "issues_found": 0,
      "details": []
    },
    "regression": {
      "pass": true,
      "tests_broken": 0,
      "details": []
    }
  },
  "recommendation": "merge | rework | block",
  "notes": "All checks passed."
}
```

### Verdict Logic

| Condition | Verdict | Recommendation |
|-----------|---------|----------------|
| All 5 checks pass | pass | merge |
| Minor issues (1-2 lint warnings, non-critical) | partial | merge with notes |
| Any AC unverified | fail | rework |
| Stubs found in implementation | fail | rework |
| Security issue found | fail | block (needs human review) |
| Regression detected | fail | rework |

## FAILURE HANDLING

When a spec fails review:
1. Update spec status to `in-progress`
2. Add failure details to the spec's Dev Agent Record:
   ```markdown
   ### Review Failure ({date})
   - Check: {which check failed}
   - Details: {specific failure}
   - Recommendation: {rework or block}
   ```
3. The spec will be re-queued by fleet-run in the next wave (max 3 attempts)
4. On 3rd failure → mark as `blocked` with full failure history

## ARGUMENTS

- `{spec-ids}` — Review specific specs
- `--all` — Review all complete specs without passing reviews
- `--check {name}` — Run only one check (compliance, stubs, quality, security, regression)
- `--verbose` — Include full grep/lint output in review file
