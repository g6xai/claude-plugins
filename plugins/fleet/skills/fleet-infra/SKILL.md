---
name: fleet-infra
description: Set up test infrastructure, CI pipeline hardening, and quality gates for autonomous development. Detects what is missing from the project manifest and installs/configures it. Run after specs exist, before fleet-run. Adapts to any tech stack.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Agent
context: fork
---

# Fleet Infra — Infrastructure Bootstrap

You prepare a repository for autonomous agent-driven development by ensuring test infrastructure, CI, and quality gates are all in place and working.

## PREREQUISITES

Read `_fleet/manifest.json` (if exists) for detected stack. If no manifest, detect stack yourself by scanning package.json, pyproject.toml, go.mod, Cargo.toml, etc.

## CRITICAL RULES

1. **Do not break what works.** All changes must be additive. Never remove existing configs.
2. **Detect before installing.** Check if a tool is already installed/configured before adding it.
3. **Use project conventions.** If the project uses pnpm, don't use npm. If it uses vitest, don't install jest.
4. **Commit after each section.** Infrastructure changes should be committed incrementally.
5. **Verify after setup.** Run each tool after configuring to confirm it works.

## PHASE 1: Test Framework

### Detection
```
Check for existing test config:
  vitest.config.ts/js → Vitest
  jest.config.ts/js → Jest
  pytest.ini / pyproject.toml [tool.pytest] → Pytest
  *_test.go → Go built-in
  Cargo.toml → Rust built-in
  build.gradle / pom.xml → JUnit
```

### If NO test framework:

| Language | Install | Config |
|----------|---------|--------|
| TypeScript/JS | `{pm} add -D vitest` | Create `vitest.config.ts` |
| Python | `pip install pytest` | Create `pytest.ini` |
| Go | Built-in | No config needed |
| Rust | Built-in | No config needed |
| Java | Add JUnit 5 dependency | Update build config |

After installing:
1. Create minimal config file following project conventions
2. Create ONE sample test that imports real code and makes a real assertion
3. Add `test` script to package.json / pyproject.toml / Makefile
4. Run: verify test passes

### If test framework exists but broken:
1. Diagnose: missing deps, bad config, version mismatch
2. Fix configuration
3. Note which tests are genuinely failing vs config failures
4. Run: verify fixed

### If test framework exists and works:
Note it and move on.

## PHASE 2: E2E Framework (Web Apps Only)

Skip if project is not a web application (no HTML routes, no frontend framework).

### Detection
```
playwright.config.ts → Playwright
cypress.config.ts → Cypress
```

### If NO E2E framework (and project is a web app):

Install Playwright (preferred for new setups):
```bash
{pm} add -D @playwright/test
npx playwright install chromium
```

Create `playwright.config.ts`:
```typescript
import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './e2e',
  use: { baseURL: 'http://localhost:3000', headless: true },
  webServer: { command: '{pm} dev', port: 3000, reuseExistingServer: true },
});
```

Create `e2e/smoke.spec.ts` — basic smoke test that verifies the app loads.

Add scripts: `test:e2e` to package.json.

## PHASE 3: CI Pipeline

### Detection
```
.github/workflows/*.yml → GitHub Actions
.gitlab-ci.yml → GitLab CI
.circleci/config.yml → CircleCI
Jenkinsfile → Jenkins
.buildkite/pipeline.yml → Buildkite
```

### If NO CI exists:

Create `.github/workflows/ci.yml` (GitHub Actions is the default):

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: {appropriate setup action}
      - run: {install dependencies}
      - run: {lint command}
      - run: {typecheck command}
      - run: {test command}
      - run: {build command}
```

Adapt the workflow to the detected stack (Node.js setup for JS, Python setup for Python, etc.).

### If CI exists but gaps:

Check which gates are present:
- [ ] Lint
- [ ] Type check
- [ ] Unit tests
- [ ] Build
- [ ] E2E tests (optional — add later when stable)

Add missing gates as new steps (don't modify existing steps).

## PHASE 4: Fleet Working Directory

Create `_fleet/` structure:
```
_fleet/
├── .gitignore
├── manifest.json      (from fleet-discover, if run)
├── manifest.md
├── assessment.json    (from fleet-assess, if run)
├── assessment.md
├── specs/             (from fleet-specgen, if run)
├── reviews/           (from fleet-review, during runs)
├── dep-graph.json
└── sync-state.json    (from fleet-sync)
```

Create `_fleet/.gitignore`:
```
run-progress.md
*.log
sync-state.json
```

Add `_fleet/` entry to root `.gitignore` if appropriate (specs should be tracked, runtime state should not).

## PHASE 5: Fleet Guard (Hooks)

Run fleet-guard to install process enforcement hooks:
```
Invoke fleet-guard skill
```

## PHASE 6: Verify Everything

Run a quick sanity check with detected commands:
1. Test runner works: `{pm} test`
2. Linter works: `{pm} lint` (if applicable)
3. Types check: `{pm} tsc --noEmit` (if TypeScript)
4. Build works: `{pm} build` (if build script exists)

Report results for each.

## PHASE 7: Commit and Report

1. Stage all infrastructure changes
2. Commit: `chore: bootstrap Fleet infrastructure (test, CI, hooks)`
3. Output summary:

```
FLEET INFRA COMPLETE
====================
Test framework: {name} — {installed/existing/fixed}
E2E framework: {name} — {installed/existing/skipped}
CI pipeline: {platform} — {created/updated/existing}
  Gates: {lint, typecheck, test, build}
Hooks: {count} installed (mode: advisory)
Fleet directory: _fleet/ created

All checks passing: {yes/no}

Next step: /fleet-sync to push to Linear/Notion, or /fleet-run to start building.
```

## ARGUMENTS

- No arguments: Full infrastructure setup
- `--test-only`: Only set up test framework
- `--ci-only`: Only set up CI pipeline
- `--hooks-only`: Only install hooks (via fleet-guard)
- `--dry-run`: Show what would be installed without doing it
- `--skip-commit`: Don't commit changes
