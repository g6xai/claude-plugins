# CLAUDE.md — G26x AI

This repository operates under the **G26x Agent Operating System**.

## Canonical sources

- **Constitution (read first):** https://github.com/g6xai/g26x-agent-os/blob/main/CLAUDE.md
- **Spec:** https://github.com/g6xai/g26x-agent-os/blob/main/docs/G26x_Agent_OS_v1.1.md
- **Agent contracts:** synchronized from `g26x-agent-os` into `.claude/agents/` in this repo (see sync workflow).

## Entity overlay (read second)

- `CLAUDE.g26xai.md` in this repo — defines this entity's compliance bar, specialists to invoke, brand notes, and escalation path.

## Order of precedence

If any document conflicts:

1. G26x Command Center PRD v2.1 (highest authority)
2. Canonical constitution (`g26x-agent-os/CLAUDE.md`)
3. Entity overlay (`CLAUDE.g26xai.md`)
4. Anything else

## Do not edit agent contracts here

Agent contracts (`.claude/agents/`) in this repo are mirrored from the canonical `g26x-agent-os` repo. Any change to agent behavior is a PR against `g26x-agent-os`, not this repo. Local edits are detected by CI and will fail the PR check.
