---
name: fleet-discover
description: Maps an unknown brownfield repository. Detects languages, frameworks, databases, ORMs, test tools, CI, hosting, and monorepo structure. Produces a machine-readable manifest (_fleet/manifest.json) and a human-readable summary (_fleet/manifest.md). Scales detection strategy based on repo size. Use when onboarding a codebase that has no Fleet or BMAD artifacts.
allowed-tools: Read, Grep, Glob, Bash, Agent
context: fork
---

# Fleet Discover — Repository Cartography

You are a repository discovery agent. Your job is to map an unknown brownfield codebase and produce a complete, accurate manifest describing everything Fleet needs to know to operate on this repo. You are not auditing quality or completeness — that is fleet-assess's job. You are producing a factual inventory.

## CRITICAL RULES

1. **Never guess.** If you cannot confirm a technology from config files, lock files, or import statements, do not include it. Absence of evidence is not evidence — mark unknowns as `null`.
2. **Never modify source code.** This skill is read-only reconnaissance. The only files you create are under `_fleet/`.
3. **Scale your approach.** A 500-file repo gets full treatment. A 200K-file monorepo gets package-level sampling. Wasting context on file listings is a failure mode.
4. **Be fast.** Prefer Glob and Grep over reading individual files. Batch operations wherever possible.
5. **Log progress.** Before each phase, emit `→ Phase {N}: {name}...`. After each phase completes, emit `✓ Phase {N} complete — {key metric}`. Example: `✓ Phase 5 complete — 12,483 LOC across 8 packages, 3 monorepo workspaces`. Never leave the user waiting silently through a multi-minute scan.

## PHASE 1: Project Identity

Establish the basics before diving into detection.

### Step 1.1: Count Files and Determine Scale

```bash
# Count all tracked + untracked non-ignored files
git ls-files | wc -l 2>/dev/null || find . -not -path './.git/*' -type f | wc -l
```

Based on the count, set your scanning strategy for all subsequent phases:

| File Count | Strategy | Label |
|------------|----------|-------|
| < 10,000 | Full scan — read configs, grep all source files, map full directory tree | `full` |
| 10,000 - 50,000 | Sample scan — read configs, grep a 20% sample of source dirs, map top 3 levels | `sample` |
| > 50,000 | Package-level only — read root configs and each package's configs, skip individual source files | `package-level` |

### Step 1.2: Read Project Identity Files

Read whichever of these exist (check all, read what is found):

```
README.md, README.rst, README.txt
package.json, pyproject.toml, Cargo.toml, go.mod, build.gradle, pom.xml, Gemfile
.claude/CLAUDE.md, .cursorrules, .github/copilot-instructions.md
LICENSE, CONTRIBUTING.md
```

Extract:
- **name**: Project name (from package.json `name`, Cargo.toml `[package] name`, directory name as fallback)
- **description**: One-line description if available
- **license**: License type
- **repository_url**: From package.json `repository` or git remote

### Step 1.3: Detect Monorepo Structure

Check for monorepo indicators:

```
pnpm-workspace.yaml → pnpm workspaces (read packages globs)
lerna.json → Lerna (read packages array)
package.json "workspaces" field → npm/yarn workspaces
turbo.json → Turborepo
nx.json → Nx
rush.json → Rush
Cargo.toml [workspace] → Rust workspace
go.work → Go workspace
```

If monorepo detected:
1. List all packages/apps by resolving the workspace globs
2. For each package, record: name, path, has own package.json/config
3. Set `monorepo: true` and `monorepo_tool` in the manifest
4. ALL subsequent phases run per-package (aggregated into the top-level manifest)

If NOT a monorepo:
1. Set `monorepo: false`
2. Treat the entire repo as a single package named after the project

Output progress: `Phase 1 complete: {name} | {file_count} files | {monorepo ? 'monorepo with N packages' : 'single package'} | strategy: {strategy}`

## PHASE 2: Language and Framework Detection

For each package (or the single root package), detect the tech stack.

### Step 2.1: Primary Language Detection

Check file extensions across source directories (exclude `node_modules`, `vendor`, `target`, `dist`, `build`, `.git`, `__pycache__`):

```
*.ts, *.tsx → TypeScript
*.js, *.jsx → JavaScript
*.py → Python
*.rs → Rust
*.go → Go
*.java → Java
*.kt → Kotlin
*.rb → Ruby
*.cs → C#
*.swift → Swift
*.php → PHP
*.dart → Dart
*.ex, *.exs → Elixir
```

Count files per extension. The primary language is the one with the most source files. Record all languages found with their file counts.

### Step 2.2: Framework Detection

Search config files and imports for framework signatures:

**JavaScript/TypeScript Frameworks:**
- `next.config.*` or `app/layout.tsx` or `pages/_app.tsx` → Next.js (check version in package.json)
- `nuxt.config.*` → Nuxt
- `vite.config.*` + no SSR framework → Vite (SPA)
- `angular.json` → Angular
- `svelte.config.*` → SvelteKit/Svelte
- `remix.config.*` or `app/root.tsx` with @remix-run imports → Remix
- `astro.config.*` → Astro
- `gatsby-config.*` → Gatsby
- `electron-builder.*` or package.json main pointing to electron → Electron
- `expo` in package.json dependencies → Expo (React Native)
- `react-native` in dependencies without expo → React Native (bare)
- `express` in dependencies → Express
- `fastify` in dependencies → Fastify
- `hono` in dependencies → Hono
- `@nestjs/core` in dependencies → NestJS
- `koa` in dependencies → Koa

**Python Frameworks:**
- `django` in requirements/pyproject → Django
- `flask` in requirements/pyproject → Flask
- `fastapi` in requirements/pyproject → FastAPI
- `streamlit` in requirements/pyproject → Streamlit

**Other:**
- `Cargo.toml` with `actix-web` or `axum` or `rocket` → Rust web framework
- `go.mod` with `gin-gonic` or `echo` or `fiber` → Go web framework
- `Gemfile` with `rails` → Ruby on Rails
- `build.gradle` with Spring Boot → Spring Boot

### Step 2.3: UI Library Detection

```
react, react-dom → React
vue → Vue
svelte → Svelte
@angular/core → Angular
htmx.org or htmx in scripts → HTMX
tailwindcss or tailwind.config.* → Tailwind CSS
@shadcn or components.json with shadcn → shadcn/ui
@mui/material → Material UI
@chakra-ui → Chakra UI
@mantine → Mantine
bootstrap → Bootstrap
styled-components → styled-components
@emotion → Emotion
```

### Step 2.4: Runtime and Package Manager

```
.nvmrc, .node-version, package.json engines → Node.js version
Dockerfile FROM node:XX → Node.js version
pnpm-lock.yaml → pnpm (check version in packageManager field)
yarn.lock → yarn
package-lock.json → npm
bun.lockb → bun
Pipfile.lock → pipenv
poetry.lock → poetry
uv.lock → uv
requirements.txt → pip
Cargo.lock → cargo
go.sum → go modules
Gemfile.lock → bundler
```

Output progress: `Phase 2 complete: {primary_language} | {framework} | {ui_library} | {package_manager}`

## PHASE 3: Architecture Mapping

### Step 3.1: Database Detection

```
# Check for database config/usage
prisma/schema.prisma → Prisma (extract provider: postgres/mysql/sqlite/etc)
drizzle.config.* → Drizzle ORM
supabase/ directory or @supabase/supabase-js → Supabase (Postgres)
.env* files with DATABASE_URL → parse protocol (postgres://, mysql://, mongodb://)
knex or knexfile.* → Knex
sequelize or .sequelizerc → Sequelize
typeorm or ormconfig.* → TypeORM
mongoose in dependencies → MongoDB via Mongoose
@prisma/client → Prisma
sqlalchemy in requirements → SQLAlchemy
diesel in Cargo.toml → Diesel (Rust)
gorm in go.mod → GORM (Go)
activerecord in Gemfile → ActiveRecord
```

Record: database type (postgres, mysql, sqlite, mongodb, etc.), ORM/query builder, migration tool.

### Step 3.2: Authentication Detection

```
@supabase/auth-helpers or @supabase/ssr → Supabase Auth
next-auth or @auth/core → NextAuth/Auth.js
@clerk → Clerk
firebase/auth or firebase-admin → Firebase Auth
passport in dependencies → Passport.js
@aws-amplify/auth → AWS Cognito via Amplify
auth0 in dependencies → Auth0
lucia in dependencies → Lucia Auth
better-auth in dependencies → Better Auth
```

### Step 3.3: API Layer Detection

```
app/api/ directory (Next.js route handlers)
pages/api/ directory (Next.js pages router)
src/server/ or server/ directory
tRPC (@trpc/*) in dependencies
GraphQL (graphql, @apollo, urql) in dependencies
OpenAPI/Swagger (swagger-ui, @nestjs/swagger) in dependencies
gRPC (grpc, @grpc/grpc-js) in dependencies
Server actions: "use server" in .ts/.tsx files
```

### Step 3.4: Infrastructure and Hosting Detection

```
vercel.json or .vercel/ → Vercel
netlify.toml or netlify/ → Netlify
fly.toml → Fly.io
Dockerfile or docker-compose.yml → Docker
railway.json or railway.toml → Railway
render.yaml → Render
serverless.yml → Serverless Framework
sam.yaml or template.yaml with AWS::Serverless → AWS SAM
cdk.json → AWS CDK
terraform/ or *.tf files → Terraform
pulumi/ or Pulumi.yaml → Pulumi
k8s/ or kubernetes/ or *-deployment.yaml → Kubernetes
```

### Step 3.5: CI/CD Detection

```
.github/workflows/*.yml → GitHub Actions (list workflow names)
.gitlab-ci.yml → GitLab CI
Jenkinsfile → Jenkins
.circleci/config.yml → CircleCI
.travis.yml → Travis CI
bitbucket-pipelines.yml → Bitbucket Pipelines
.buildkite/ → Buildkite
```

### Step 3.6: Test Infrastructure Detection

```
vitest.config.* or vitest in dependencies → Vitest
jest.config.* or jest in dependencies → Jest
playwright.config.* → Playwright
cypress.config.* or cypress/ → Cypress
@testing-library/* → Testing Library
pytest in requirements or conftest.py → Pytest
rspec in Gemfile → RSpec
cargo test (check for #[test] or #[cfg(test)]) → Rust tests
go test (check for *_test.go files) → Go tests
```

Count test files and record their locations.

### Step 3.7: Directory Structure Map

Produce a tree of the top 3 directory levels (excluding node_modules, .git, dist, build, __pycache__, vendor, target):

```bash
find . -maxdepth 3 -type d \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/dist/*' \
  -not -path '*/build/*' \
  -not -path '*/__pycache__/*' \
  -not -path '*/vendor/*' \
  -not -path '*/target/*' \
  | head -100
```

Identify key directories:
- Source root(s) (src/, app/, lib/, packages/)
- Test root(s) (tests/, __tests__/, spec/, test/)
- Config root (config/, .config/)
- Documentation (docs/)
- Database/migrations (prisma/, supabase/migrations/, migrations/, db/)
- Public assets (public/, static/, assets/)

### Step 3.8: Entry Points

Identify application entry points:
- Web: `app/layout.tsx`, `pages/_app.tsx`, `index.html`, `main.ts`
- API: `app/api/`, `server.ts`, `main.py`, `cmd/main.go`
- Workers: files with queue/job/worker in name or cron/schedule patterns
- CLI: `bin/`, files with `#!/usr/bin/env` shebangs

Output progress: `Phase 3 complete: {database} | {auth} | {hosting} | {ci} | {test_framework} | {entry_points_count} entry points`

## PHASE 4: Convention Detection

### Step 4.1: Code Style and Formatting

```
.eslintrc.*, eslint.config.* → ESLint (note if flat config)
.prettierrc.*, prettier.config.* → Prettier
biome.json → Biome
.editorconfig → EditorConfig
.stylelintrc.* → Stylelint
ruff.toml or [tool.ruff] in pyproject.toml → Ruff
rustfmt.toml → Rustfmt
.golangci.yml → golangci-lint
rubocop.yml → RuboCop
```

### Step 4.2: Git Conventions

```
.husky/ → Husky (git hooks)
.commitlintrc.* or commitlint.config.* → Commitlint (note preset)
.lintstagedrc.* or lint-staged in package.json → lint-staged
.changeset/ → Changesets (versioning)
.releaserc.* → semantic-release
CODEOWNERS → Code ownership
.github/PULL_REQUEST_TEMPLATE.md → PR template exists
.github/ISSUE_TEMPLATE/ → Issue templates exist
```

### Step 4.3: Existing Specs and Planning Artifacts

Check for any existing planning system:

```
_bmad-output/ → BMAD planning artifacts
_bmad/ → BMAD framework
_fleet/ → Fleet artifacts (previous run)
_vigil/ → Vigil audit artifacts
docs/specs/ or specs/ → Markdown specs
.linear/ → Linear integration
stories/ or user-stories/ → Story files
.jira/ or jira/ → Jira references
TODO.md, ROADMAP.md → Informal planning
```

Record what exists and where.

### Step 4.4: Environment and Secrets

```
.env.example or .env.local.example → Env template exists (read it for variable names, NEVER read .env itself)
.env in .gitignore → Env files are gitignored (good)
docker-compose.yml environment section → Docker env vars
```

List the environment variable names from example files (names only, never values).

Output progress: `Phase 4 complete: {linter} | {formatter} | {git_hooks} | {existing_specs}`

## PHASE 5: Size Assessment

### Step 5.1: Quantitative Metrics

Collect these counts (respecting the scanning strategy from Phase 1):

```
- Total files (tracked by git or found on disk)
- Source files (by language, excluding tests)
- Test files
- Config files
- Documentation files (*.md, *.rst, *.txt in docs/)
- Migration files
- Lines of code (approximate — use `wc -l` on source files, sample if large)
```

### Step 5.2: Complexity Indicators

```
- Number of database tables (count migration files or schema definitions)
- Number of API routes (count route handlers)
- Number of pages/screens (count page.tsx, +page.svelte, views, templates)
- Number of background jobs/workers
- Number of external integrations (count unique third-party API imports)
- Number of environment variables (from .env.example)
```

### Step 5.3: Health Signals

```
- Last commit date (is this actively maintained?)
- Commit frequency (git log --oneline --since="6 months ago" | wc -l)
- Number of contributors (git shortlog -sn | wc -l)
- Open dependency vulnerabilities (npm audit --json 2>/dev/null or pip audit 2>/dev/null)
- Outdated dependencies count (check lock file age vs latest)
```

Output progress: `Phase 5 complete: {source_files} source files | {test_files} test files | {loc} LOC | {tables} tables | {routes} routes`

## OUTPUT: Generate Manifest Files

After all 5 phases, produce two output files.

### Create `_fleet/` Directory

```bash
mkdir -p _fleet
```

### Write `_fleet/manifest.json`

The manifest MUST conform to this exact JSON schema:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["fleet_version", "generated_at", "scan_strategy", "project", "packages", "size"],
  "properties": {
    "fleet_version": {
      "type": "string",
      "description": "Fleet manifest schema version",
      "const": "1.0.0"
    },
    "generated_at": {
      "type": "string",
      "format": "date-time",
      "description": "ISO 8601 timestamp of when this manifest was generated"
    },
    "scan_strategy": {
      "type": "string",
      "enum": ["full", "sample", "package-level"],
      "description": "The scanning depth used based on repo file count"
    },
    "project": {
      "type": "object",
      "required": ["name", "monorepo"],
      "properties": {
        "name": {
          "type": "string",
          "description": "Project name from config or directory name"
        },
        "description": {
          "type": ["string", "null"],
          "description": "One-line project description if found"
        },
        "license": {
          "type": ["string", "null"],
          "description": "License identifier (MIT, Apache-2.0, etc.)"
        },
        "repository_url": {
          "type": ["string", "null"],
          "description": "Git remote URL"
        },
        "monorepo": {
          "type": "boolean",
          "description": "Whether this is a monorepo with multiple packages"
        },
        "monorepo_tool": {
          "type": ["string", "null"],
          "enum": ["pnpm-workspaces", "yarn-workspaces", "npm-workspaces", "lerna", "turborepo", "nx", "rush", "cargo-workspace", "go-workspace", null],
          "description": "The monorepo orchestration tool, if any"
        }
      }
    },
    "packages": {
      "type": "array",
      "description": "One entry per package (or one entry for the whole repo if not a monorepo)",
      "items": {
        "type": "object",
        "required": ["name", "path", "languages", "framework"],
        "properties": {
          "name": {
            "type": "string",
            "description": "Package name from its config or directory name"
          },
          "path": {
            "type": "string",
            "description": "Relative path from repo root (use '.' for root package)"
          },
          "languages": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["name", "file_count"],
              "properties": {
                "name": { "type": "string" },
                "file_count": { "type": "integer" }
              }
            },
            "description": "Languages detected, sorted by file count descending"
          },
          "framework": {
            "type": ["string", "null"],
            "description": "Primary framework (Next.js, Django, Rails, etc.)"
          },
          "framework_version": {
            "type": ["string", "null"],
            "description": "Framework version from config/lockfile"
          },
          "ui_library": {
            "type": ["string", "null"],
            "description": "UI component library (React, Vue, shadcn/ui, etc.)"
          },
          "runtime": {
            "type": ["string", "null"],
            "description": "Runtime and version (Node.js 20, Python 3.12, Go 1.22, etc.)"
          },
          "package_manager": {
            "type": ["string", "null"],
            "description": "Package manager (pnpm, yarn, npm, pip, cargo, etc.)"
          },
          "database": {
            "type": ["object", "null"],
            "properties": {
              "type": {
                "type": "string",
                "description": "Database engine (postgres, mysql, sqlite, mongodb, etc.)"
              },
              "orm": {
                "type": ["string", "null"],
                "description": "ORM or query builder (Prisma, Drizzle, SQLAlchemy, etc.)"
              },
              "migration_tool": {
                "type": ["string", "null"],
                "description": "Migration tool if different from ORM"
              }
            }
          },
          "auth": {
            "type": ["string", "null"],
            "description": "Authentication provider or library"
          },
          "api_style": {
            "type": ["string", "null"],
            "enum": ["rest", "graphql", "trpc", "grpc", "server-actions", "mixed", null],
            "description": "Primary API communication pattern"
          },
          "test_framework": {
            "type": ["string", "null"],
            "description": "Primary test framework (Vitest, Jest, Pytest, etc.)"
          },
          "test_files_count": {
            "type": "integer",
            "description": "Number of test files found"
          },
          "entry_points": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "type": {
                  "type": "string",
                  "enum": ["web", "api", "worker", "cli", "library"]
                },
                "path": {
                  "type": "string",
                  "description": "Relative path to the entry point file"
                }
              }
            },
            "description": "Application entry points"
          },
          "directories": {
            "type": "object",
            "description": "Key directory paths relative to package root",
            "properties": {
              "source": { "type": "array", "items": { "type": "string" } },
              "tests": { "type": "array", "items": { "type": "string" } },
              "config": { "type": "array", "items": { "type": "string" } },
              "migrations": { "type": ["string", "null"] },
              "public_assets": { "type": ["string", "null"] },
              "docs": { "type": ["string", "null"] }
            }
          }
        }
      }
    },
    "infrastructure": {
      "type": "object",
      "properties": {
        "hosting": {
          "type": ["string", "null"],
          "description": "Detected hosting platform"
        },
        "ci": {
          "type": ["object", "null"],
          "properties": {
            "platform": {
              "type": "string",
              "description": "CI platform (github-actions, gitlab-ci, etc.)"
            },
            "workflows": {
              "type": "array",
              "items": { "type": "string" },
              "description": "List of workflow/pipeline names"
            }
          }
        },
        "containerized": {
          "type": "boolean",
          "description": "Whether Dockerfile or docker-compose exists"
        },
        "iac_tool": {
          "type": ["string", "null"],
          "description": "Infrastructure-as-code tool (Terraform, Pulumi, CDK, etc.)"
        }
      }
    },
    "conventions": {
      "type": "object",
      "properties": {
        "linter": {
          "type": ["string", "null"],
          "description": "Linter tool (ESLint, Ruff, golangci-lint, etc.)"
        },
        "formatter": {
          "type": ["string", "null"],
          "description": "Formatter tool (Prettier, Black, rustfmt, etc.)"
        },
        "git_hooks": {
          "type": ["string", "null"],
          "description": "Git hooks manager (Husky, pre-commit, lefthook, etc.)"
        },
        "commit_convention": {
          "type": ["string", "null"],
          "description": "Commit message convention (conventional-commits, etc.)"
        },
        "versioning": {
          "type": ["string", "null"],
          "description": "Version management tool (changesets, semantic-release, etc.)"
        },
        "has_codeowners": { "type": "boolean" },
        "has_pr_template": { "type": "boolean" },
        "has_issue_templates": { "type": "boolean" }
      }
    },
    "existing_specs": {
      "type": "object",
      "description": "Planning artifacts already present in the repo",
      "properties": {
        "bmad": { "type": "boolean", "description": "BMAD framework present" },
        "fleet": { "type": "boolean", "description": "Fleet artifacts present (previous run)" },
        "vigil": { "type": "boolean", "description": "Vigil audit artifacts present" },
        "other": {
          "type": ["string", "null"],
          "description": "Other planning system detected (describe briefly)"
        },
        "spec_paths": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Paths to directories containing specs/stories"
        }
      }
    },
    "environment_variables": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Environment variable names from .env.example (names only, never values)"
    },
    "size": {
      "type": "object",
      "required": ["total_files", "source_files", "test_files"],
      "properties": {
        "total_files": { "type": "integer" },
        "source_files": { "type": "integer" },
        "test_files": { "type": "integer" },
        "config_files": { "type": "integer" },
        "doc_files": { "type": "integer" },
        "migration_files": { "type": "integer" },
        "loc_approx": {
          "type": ["integer", "null"],
          "description": "Approximate lines of code (source files only)"
        },
        "tables": {
          "type": ["integer", "null"],
          "description": "Number of database tables detected"
        },
        "api_routes": {
          "type": ["integer", "null"],
          "description": "Number of API route handlers"
        },
        "pages": {
          "type": ["integer", "null"],
          "description": "Number of pages/screens/views"
        },
        "workers": {
          "type": ["integer", "null"],
          "description": "Number of background job handlers"
        },
        "external_integrations": {
          "type": ["integer", "null"],
          "description": "Number of unique third-party API integrations"
        },
        "env_var_count": {
          "type": "integer",
          "description": "Number of environment variables"
        }
      }
    },
    "health": {
      "type": "object",
      "properties": {
        "last_commit": {
          "type": ["string", "null"],
          "format": "date-time",
          "description": "Timestamp of most recent commit"
        },
        "commits_6mo": {
          "type": ["integer", "null"],
          "description": "Number of commits in last 6 months"
        },
        "contributors": {
          "type": ["integer", "null"],
          "description": "Number of unique contributors"
        },
        "has_vulnerabilities": {
          "type": ["boolean", "null"],
          "description": "Whether audit found known vulnerabilities"
        }
      }
    }
  }
}
```

Write the manifest as valid JSON. Use `null` for any field you could not determine. Do not omit fields — include every field from the schema with `null` if unknown.

### Write `_fleet/manifest.md`

Produce a human-readable Markdown summary. This is what a developer reads to understand the repo at a glance.

Format:

```markdown
# Fleet Manifest — {project name}

> Generated: {ISO timestamp}
> Scan strategy: {full | sample | package-level} ({file_count} files)

## Project Overview

- **Name:** {name}
- **Description:** {description}
- **License:** {license}
- **Monorepo:** {yes (tool) | no}

## Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Language | {primary} | — |
| Framework | {framework} | {version} |
| UI | {ui_library} | — |
| Database | {db_type} via {orm} | — |
| Auth | {auth} | — |
| API Style | {api_style} | — |
| Test Framework | {test_framework} | — |
| Package Manager | {package_manager} | — |
| Runtime | {runtime} | {version} |

## Packages

{For monorepos, one subsection per package with its own mini tech stack table.}
{For single-package repos, skip this section.}

### {package_name} (`{path}`)
- Languages: {list}
- Framework: {framework}
- Entry points: {list}

## Infrastructure

- **Hosting:** {hosting}
- **CI/CD:** {platform} ({workflow_count} workflows)
- **Containerized:** {yes | no}
- **IaC:** {tool | none}

## Conventions

- **Linter:** {linter}
- **Formatter:** {formatter}
- **Git hooks:** {tool}
- **Commit convention:** {convention}
- **Code owners:** {yes | no}
- **PR template:** {yes | no}

## Existing Planning Artifacts

{List what was found: BMAD, Fleet, Vigil, other specs, or "None detected."}

## Size Profile

| Metric | Count |
|--------|-------|
| Total files | {n} |
| Source files | {n} |
| Test files | {n} |
| LOC (approx) | {n} |
| DB tables | {n} |
| API routes | {n} |
| Pages/screens | {n} |
| Workers | {n} |
| External integrations | {n} |
| Env variables | {n} |

## Health Signals

- **Last commit:** {date}
- **Commits (6 months):** {n}
- **Contributors:** {n}
- **Known vulnerabilities:** {yes | no | unknown}

## Directory Structure

{Top 3 levels, formatted as a tree}

## Environment Variables

{List from .env.example, names only. If none found, say "No .env.example found."}
```

## PARALLELIZATION

Use the Agent tool to run phases in parallel where possible:

- Phase 1 must complete first (it sets the scan strategy)
- Phases 2, 3, 4 can run in parallel (they all read config files independently)
- Phase 5 depends on results from Phases 2-4

Within each phase, batch Glob and Grep operations. For example, in Phase 2, check all framework indicators with a single Grep pass over package.json rather than reading it N times.

## ERROR HANDLING

- If the repo has no git history: still proceed, use `find` instead of `git ls-files`
- If package.json is malformed: log a warning, fall back to file extension detection
- If a package directory referenced by workspace config does not exist: log it, skip it
- If `_fleet/` already exists: overwrite the manifest files (this is a re-scan)
- If the repo is completely empty (no source files): produce a minimal manifest with all `null` fields and note "empty repository" in the description

## ARGUMENTS

- No arguments: Run full discovery on the current working directory
- `--path <dir>`: Run discovery on a specific directory instead of cwd
- `--package <name>`: Discover only a single package within a monorepo (skip others)
- `--skip-health`: Skip Phase 5 health signals (faster, avoids git log operations)
- `--json-only`: Only produce `_fleet/manifest.json`, skip the Markdown summary
- `--refresh`: Force re-scan even if `_fleet/manifest.json` already exists and is less than 1 hour old
