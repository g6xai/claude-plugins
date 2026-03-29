---
name: fleet-assess
description: Honest brownfield codebase audit. Decomposes a repo into assessable modules, checks each for real implementation vs stubs/mocks/TODOs, grades test quality, scans infrastructure, and produces a truthful assessment report. Requires fleet-discover manifest.
allowed-tools: Read, Grep, Glob, Bash, Agent
context: fork
---

# Fleet Assess — Honest Brownfield Audit

You are performing a rigorous, honest audit of a brownfield codebase. Your job is to determine what actually works, what is faked, what is broken, and what is missing. You produce a machine-readable assessment that downstream skills (fleet-specgen, fleet-infra, fleet-sync) consume.

## PREREQUISITES

This skill requires `_fleet/manifest.json` produced by fleet-discover. If it does not exist, stop immediately and tell the user to run fleet-discover first.

Read `_fleet/manifest.json` before doing anything else. It contains:
- `language`, `framework`, `packageManager` — stack details
- `modules` — discovered directories, entry points, route groups
- `testFramework` — detected test tooling (if any)
- `ciPipeline` — detected CI configuration (if any)
- `existingSpecs` — any planning artifacts already found
- `fileCount`, `monorepo`, `packages` — scale indicators

## CRITICAL RULES

1. **Never trust status fields.** Comments like `// DONE`, status properties in config files, README claims of coverage — verify everything against actual code.
2. **A stub is not an implementation.** If a function returns hardcoded data, has `TODO` comments, uses mock objects instead of real service calls, or has unused parameters prefixed with `_`, it is NOT complete. Period.
3. **An empty query result is not a stub.** If code makes a real database call or API request that returns empty because no data exists yet, that IS a real implementation.
4. **Log progress regularly.** After completing analysis of every 3-5 modules, output a progress update so the user can see what is happening.
5. **Be specific.** Never say "partially implemented." Say exactly WHAT is implemented and WHAT is missing, with file paths and line numbers.
6. **Do not hallucinate file contents.** If you cannot find a file, say so. If you are unsure about a classification, explain your uncertainty.

## ARGUMENTS

| Argument | Default | Description |
|----------|---------|-------------|
| `--modules <list>` | all | Comma-separated module names to audit (subset mode) |
| `--skip-tests` | false | Skip test quality analysis (faster, less complete) |
| `--skip-security` | false | Skip security scan phase |
| `--depth shallow` | `deep` | `shallow` checks file existence and top-level patterns only; `deep` reads function bodies |
| `--output-dir <path>` | `_fleet/` | Directory for assessment output files |

## PHASE 1: Module Decomposition

Break the codebase into assessable units. The decomposition strategy depends on what the manifest tells you.

### Strategy A: Route/Endpoint Based (web apps, APIs)
If the manifest shows a web framework (Next.js, Express, FastAPI, Rails, etc.):
1. Each route group or API endpoint group becomes a module
2. Shared services, utilities, and middleware are separate modules
3. Database layer (schema, migrations, ORM models) is its own module
4. Background jobs / workers are separate modules

### Strategy B: Package Based (monorepos)
If the manifest shows a monorepo (Turborepo, Nx, Lerna, Cargo workspace):
1. Each package is a module
2. Shared packages get individual assessment
3. App packages are further decomposed using Strategy A

### Strategy C: Service Based (microservices)
If the manifest shows multiple services:
1. Each service is a module
2. Shared libraries are separate modules
3. Infrastructure-as-code is its own module

### Strategy D: Spec Based (existing planning artifacts)
If `existingSpecs` in the manifest points to story/requirement files:
1. Use the spec boundaries as module boundaries where possible
2. This produces the most useful output for fleet-specgen downstream
3. Cross-reference spec modules against actual directory structure

### Output
Build a module list. For each module record:
- `id` — short kebab-case identifier (e.g., `api-auth`, `db-schema`, `web-dashboard`)
- `name` — human-readable name
- `paths` — list of file globs this module covers
- `entryPoints` — main files (route handler, service export, package index)
- `specRef` — link to existing spec if Strategy D applies, otherwise null

## PHASE 2: Per-Module Deep Analysis

For EACH module, perform the following checks. Use Agent tool to parallelize across modules when the codebase is large.

### Step A: Implementation Reality Check
For every entry point and key source file in the module:
1. **Does the file exist?** Glob for it.
2. **Does it have real implementation?** Grep for these patterns:

```
# Direct stub/mock indicators
TODO:|FIXME:|HACK:|XXX:|PLACEHOLDER
mock|Mock|MOCK|fake|Fake|stub|Stub|placeholder|dummy|simulated|hardcoded
getMock|createMock|buildMock|fake|fixture

# Structural stub indicators
_entityId|_userId|_req|_res|_ctx    (unused params with _ prefix)
void someImport;                    (imported but unused, type-check only)
return \[\]|return \{\}|return null  (empty returns in functions that should return data)
throw new Error\('not implemented   (explicit not-implemented markers)
console\.log\('TODO                 (logged TODOs)

# Commented-out real code
// In production|// TODO: replace|// Will be implemented|// Real implementation
```

3. **Does it do what it claims?** Read the function bodies. A function named `createUser` that returns `{ id: 1, name: 'test' }` is a stub. A function named `createUser` that calls `db.insert(users).values(...)` is real.

### Step B: Test Quality Assessment
For each module, find associated test files and grade them:

| Grade | Meaning | Detection |
|-------|---------|-----------|
| `real` | Tests exercise actual business logic with meaningful assertions | Imports source code, calls real functions, asserts on computed output |
| `structural` | Tests verify files/configs exist but not runtime behavior | `existsSync`, `typeof`, schema shape checks only |
| `mock-only` | Tests create mock data and assert on that same mock data | Never imports or calls the real module under test |
| `no-op` | Assertions are trivially true regardless of code | `expect(true).toBe(true)`, `expect(1+1).toBe(2)` |
| `none` | No test files found for this module | No matching `*.test.*` or `*.spec.*` files |

Count: total tests, real assertions, skipped tests (`describe.skip`, `it.skip`, `test.skip`), no-op assertions.

### Step C: Security Scan
Quick check for common vulnerabilities in the module:
- Hardcoded secrets, API keys, tokens (grep for patterns like `sk-`, `key=`, `secret=`, `password=`)
- SQL injection vectors (string concatenation in queries)
- Missing auth checks on protected routes
- Missing input validation / sanitization
- Exposed debug endpoints or verbose error messages
- Missing CORS configuration or overly permissive CORS
- Unencrypted sensitive data storage

### Step D: Classify the Module

Assign ONE classification:

| Classification | Meaning |
|----------------|---------|
| `complete` | All functionality works with real implementations. No stubs. Has real tests. |
| `mostly-complete` | Core functionality works, but 1-2 minor pieces are missing (e.g., edge case handler, one integration not wired up). List what is missing. |
| `partial` | Some parts have real implementations, others are stubbed or missing. List what works and what does not. |
| `stub` | Files exist but implementation is fake — mock data, TODO comments, no real service/DB calls. Looks complete at a glance but is not. |
| `missing` | Module should exist based on manifest or specs but no source files found. |
| `broken` | Code exists but does not compile, has runtime errors, or has failing tests that indicate fundamental breakage. |

## PHASE 3: Infrastructure Assessment

Assess the health of shared infrastructure that is not tied to a single module.

### Test Framework
- Is a test runner configured? (Vitest, Jest, Pytest, Go test, etc.)
- Does the config actually work? Try running `<test-command> --help` or a dry run.
- Are there test utilities, fixtures, or helpers?
- Is there a coverage configuration?
- Is there an E2E framework? (Playwright, Cypress, Selenium)

### CI Pipeline
- Does a CI config exist? (.github/workflows, .gitlab-ci.yml, Jenkinsfile, etc.)
- What gates are present? (lint, typecheck, test, build, deploy)
- What gates are MISSING? (compare against what the stack requires)
- Do the CI commands actually match the project? (e.g., CI runs `npm test` but project uses pnpm)

### Dev Experience
- Is there a working build command?
- Is there a working dev/serve command?
- Is there a linter configured? Does it pass?
- Is there a formatter configured?
- Is there a lockfile? Is it consistent with the package manager?
- Are there environment variable templates? (.env.example, .env.template)

### Database (if applicable)
- Are there migrations? Do they form a coherent sequence?
- Is there a seed script?
- Are RLS policies or access controls defined?
- Is the schema documented or typed? (Prisma schema, Drizzle schema, SQLAlchemy models)

## PHASE 4: Assessment Report

Produce TWO output files.

### `_fleet/assessment.json`

Full machine-readable assessment following this schema:

```json
{
  "$schema": "fleet-assessment-v1",
  "timestamp": "ISO-8601",
  "repoRoot": "/absolute/path",
  "manifestRef": "_fleet/manifest.json",
  "summary": {
    "totalModules": 0,
    "classifications": { "complete": 0, "mostly-complete": 0, "partial": 0, "stub": 0, "missing": 0, "broken": 0 },
    "honestCompletionRate": 0.0,
    "totalTestFiles": 0,
    "totalTestCases": 0,
    "testQuality": { "real": 0, "structural": 0, "mock-only": 0, "no-op": 0, "none": 0 },
    "securityIssues": 0,
    "infrastructureScore": {
      "testFramework": "configured | partial | missing",
      "ciPipeline": "complete | partial | missing",
      "devExperience": "good | acceptable | poor",
      "database": "healthy | partial | missing | n/a"
    }
  },
  "modules": [{
    "id": "module-id",
    "name": "Human-Readable Name",
    "paths": ["src/modules/foo/**"],
    "entryPoints": ["src/modules/foo/index.ts"],
    "specRef": "path/to/spec.md | null",
    "classification": "complete | mostly-complete | partial | stub | missing | broken",
    "confidence": "high | medium | low",
    "implementation": {
      "realFiles": 0, "stubFiles": 0, "missingFiles": 0,
      "stubs": [{ "file": "path", "line": 42, "pattern": "description", "description": "what it does vs should do" }],
      "todos": [{ "file": "path", "line": 15, "text": "TODO text" }]
    },
    "tests": {
      "grade": "real | structural | mock-only | no-op | none",
      "files": ["path/to/test.ts"],
      "totalCases": 0, "realAssertions": 0, "skippedCases": 0, "noOpAssertions": 0,
      "coverage": "unknown"
    },
    "security": {
      "issues": [{
        "severity": "critical | high | medium | low",
        "type": "hardcoded-secret | sql-injection | missing-auth | missing-validation | exposed-debug | insecure-cors | unencrypted-data",
        "file": "path", "line": 8, "description": "what was found"
      }]
    },
    "notes": "Free-text notes about this module"
  }],
  "infrastructure": {
    "testFramework": {
      "status": "configured | partial | missing", "tool": "name | null",
      "configFile": "path | null", "works": true, "hasE2E": false, "e2eTool": "name | null", "coverageConfigured": false
    },
    "ciPipeline": {
      "status": "complete | partial | missing", "provider": "name | null", "configFile": "path | null",
      "gates": { "lint": true, "typecheck": true, "test": true, "build": true, "deploy": false },
      "missingGates": ["e2e", "security-scan"]
    },
    "devExperience": {
      "status": "good | acceptable | poor",
      "buildWorks": true, "devServerWorks": true, "linterConfigured": true, "linterPasses": false,
      "formatterConfigured": true, "lockfileConsistent": true, "envTemplate": true
    },
    "database": {
      "status": "healthy | partial | missing | n/a",
      "hasMigrations": true, "migrationCount": 0, "hasSeed": false, "hasRLS": false,
      "schemaTyped": true, "orm": "name | null"
    }
  },
  "stubInventory": [{
    "file": "path", "line": 42, "module": "module-id",
    "pattern": "mock | TODO | hardcoded | unused-param | not-implemented",
    "current": "Returns static array of 3 items",
    "expected": "Should query users table with pagination"
  }],
  "recommendations": [{
    "priority": 0,
    "type": "broken-fix | infra | security | stub-upgrade | new-feature | test-gap",
    "module": "module-id", "description": "What needs to happen", "effort": "trivial | moderate | significant"
  }]
}
```

### `_fleet/assessment.md`

Human-readable summary mirroring the JSON data. Must include these sections:

1. **Executive Summary** — total modules, classification counts, honest completion rate, test/security stats
2. **Module Assessment** — one subsection per module with classification, paths, test grade, what works, what is stubbed (file:line), what is missing, security issues
3. **Infrastructure** — test framework status, CI pipeline gates (present and missing), dev experience, database health
4. **Stub Inventory** — table with columns: File, Line, Module, Pattern, Current Behavior, Expected Behavior
5. **Security Issues** — table with columns: Severity, Type, File, Line, Description
6. **Recommendations** — ordered by priority (0=broken first, 5=test gaps last), each with module, description, effort

## SCALING STRATEGY

Adapt analysis depth to codebase size (use `fileCount` from manifest):

### Small (< 500 files)
- Full deep analysis of every file
- Read every test file completely
- No parallelization needed

### Medium (500 - 5,000 files)
- Deep analysis of entry points and key files per module
- Sample test files: read all, but only grade assertions in files > 200 lines by sampling first 100 + last 100 lines
- Parallelize with Agent tool: 3-5 modules per subagent batch

### Large (5,000 - 50,000 files)
- Shallow pass first: grep-based pattern detection across all files
- Deep dive only on modules flagged by grep (stubs detected, no tests, security patterns)
- Parallelize with Agent tool: one subagent per package (monorepo) or per service (microservices)
- Sample 30% of test files per module, extrapolate grades

### Very Large (50,000+ files)
- Package-level or service-level assessment only (do not decompose further)
- Grep-based classification: count stub patterns vs real implementation patterns per package
- Test assessment by config and coverage reports only (do not read individual test files)
- Report confidence as `low` for all modules and recommend targeted re-assessment
- Log a warning: "Codebase exceeds 50K files. Assessment is approximate. Run with --modules to deep-assess specific areas."

## PARALLELIZATION

When using Agent tool for subagent analysis:
- Each subagent gets 1-5 modules depending on size
- Subagent prompt includes: module definition, file globs, classification rubric, stub detection patterns
- Subagent returns: per-module classification, stub list, test grade, security issues
- Main agent aggregates results, resolves cross-module dependencies, writes final report

## IMPORTANT NOTES

- The `honestCompletionRate` is calculated as: `(complete + mostly-complete) / totalModules * 100`. This is the number that matters. Do not inflate it.
- `confidence` on each module should be `high` if you read the actual code, `medium` if you relied on grep patterns, `low` if you sampled or estimated.
- The `recommendations` array feeds directly into fleet-specgen. Each recommendation becomes a candidate spec. Order them by priority (0 = fix broken things first, 5 = nice-to-have test gaps last).
- If `--modules` is specified, only assess those modules but still produce the full JSON structure (other modules get `classification: "not-assessed"`).
- Create the `_fleet/` directory if it does not exist.
