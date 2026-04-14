---
name: fleet-guard
description: Process enforcement for Fleet. Installs Claude Code hooks that prevent process violations — no code without specs, no merge without tests, auto-formatting, session context loading. Run by fleet-infra during setup, or manually to install/update hooks.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
context: fork
---

# Fleet Guard — Process Enforcement

You install and maintain Claude Code hooks that enforce the Fleet development process. These hooks run automatically during every Claude Code session in this repo.

## WHAT GETS ENFORCED

1. **Specs before code** — Warn when editing source files without a corresponding spec
2. **Tests before merge** — Warn when committing without tests for changed files
3. **Auto-formatting** — Run formatter after edits (if configured)
4. **Session context** — Load Fleet/BMAD context on session start
5. **Quality gate on stop** — Run tests before allowing agent to finish

## INSTALLATION

### Step 1: Read Existing Settings

Check `.claude/settings.json` for existing hooks. NEVER overwrite — always merge.

```
If file exists:
  Read current hooks array
  Merge new hooks (skip duplicates by matching hook type + event)
If file doesn't exist:
  Create with Fleet hooks only
```

### Step 2: Detect Available Tools

Check `_fleet/manifest.json` or scan for:
- Formatter: prettier, biome, black, gofmt, rustfmt
- Linter: eslint, biome, ruff, golangci-lint, clippy
- Type checker: tsc, mypy, pyright
- Test runner: vitest, jest, pytest, go test, cargo test
- Package manager: pnpm, npm, yarn, pip, cargo, go

### Step 3: Generate Hook Configuration

Write to `.claude/settings.json` (merging with existing):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "echo '🚀 Fleet active. Process: specs → tests → code → review → sync'",
        "description": "Fleet session reminder"
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "type": "command",
        "command": "{formatter-command} $CLAUDE_FILE 2>/dev/null || true",
        "description": "Fleet: auto-format after edit",
        "timeout": 10000
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit",
        "type": "prompt",
        "prompt": "Check if the file being edited has a corresponding spec in _fleet/specs/ or _bmad-output/implementation-artifacts/. If no spec covers this file, add a brief warning to your response suggesting the engineer create a spec first. Do NOT block the edit.",
        "description": "Fleet: spec-before-code advisory"
      }
    ]
  }
}
```

### Hook Details

**SessionStart — Context Loading:**
- Remind the engineer of the Fleet process
- If `_fleet/manifest.json` exists, note the detected stack
- If `_fleet/run-progress.md` exists, show last wave status

**PostToolUse(Edit|Write) — Auto-Format:**
- Only install if a formatter is detected
- Run formatter on the edited file
- Non-blocking (exit 0 always, timeout 10s)
- Supports: prettier, biome, black, gofmt, rustfmt

**PreToolUse(Edit) — Spec Advisory:**
- Lightweight prompt hook (not blocking)
- Checks if the file being edited is covered by a spec
- Warns but does NOT block — engineers can work on ad-hoc fixes

**NOTE:** Heavy enforcement (blocking edits, mandatory tests) is intentionally NOT installed by default. Engineers should adopt Fleet gradually. The hooks start as advisories and can be upgraded to blockers via `--strict` mode.

### Step 4: Strict Mode (Optional)

When `--strict` is passed, upgrade advisories to blockers:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash(git commit|git push)",
        "type": "command",
        "command": "bash -c 'CHANGED=$(git diff --cached --name-only); for f in $CHANGED; do if echo $f | grep -qE \"\\.(ts|tsx|py|go|rs|java|rb)$\"; then TEST=$(echo $f | sed \"s/\\.[^.]*$/.test&/\"); if [ ! -f \"$TEST\" ]; then echo \"WARNING: $f has no corresponding test file\" >&2; fi; fi; done'",
        "description": "Fleet: warn on commit without tests"
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "{package-manager} test 2>&1 | tail -5",
        "description": "Fleet: run tests before stopping",
        "timeout": 300000
      }
    ]
  }
}
```

### Step 5: Verify

After installing hooks:
1. Read back `.claude/settings.json` to confirm hooks are present (structural check — confirms the block was written)
2. Trigger one hook (e.g., run a trivial Read) to confirm hooks actually load, not just that the config file contains them
3. Report what was installed as a markdown table — not a prose list. Banner is ✅ when all hooks loaded, ⚠️ if config written but a hook failed to trigger:

```markdown
## ✅ Fleet Guard — Hooks Installed

| Event | Hook | Enabled | Verified |
|-------|------|---------|----------|
| SessionStart | Fleet context reminder | ✅ | ✅ |
| PostToolUse | Auto-format ({formatter}) | ✅ | ✅ |
| PreToolUse | Spec advisory (edit) | ✅ | ✅ |

- **Mode:** advisory (use `--strict` for enforcement)
- **Config:** `.claude/settings.json`

### Next Step
- To upgrade to strict mode: `/fleet-guard --strict`
- To remove Fleet hooks: `/fleet-guard --remove`
```

## ARGUMENTS

- No arguments: Install advisory hooks (default)
- `--strict`: Install enforcement hooks (block non-compliant actions)
- `--remove`: Remove all Fleet hooks from settings.json
- `--status`: Show currently installed hooks
- `--dry-run`: Show what would be installed without writing
