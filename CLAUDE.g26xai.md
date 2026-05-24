# CLAUDE.g26xai.md — Entity Overlay

# Entity: G26x AI

**Holding:** G26x Holdings
**Entity operator:** Tony Grothouse
**Escalation path:** Tony -> Daryl
**Tier on AI maturity (per PRD v2.1):** Tier 4

## Mission

G26x AI builds and operates the AI agent infrastructure, tooling, and plugins that power the entire G26x portfolio — including the Agent OS itself, entity templates, Claude plugins, and agent orchestration.

## Active products / platforms

- G26x Agent OS (canonical constitution, agent contracts, state machine)
- Entity onboarding templates
- Claude Code plugins and extensions
- Agent orchestration infrastructure

## Compliance bar

- [x] **SOC 2** — invokes `soc2-reviewer`.
- [x] **Financial controls** — invokes `financial-controls-reviewer`.

## Specialist invocation rules

| Trigger | Specialist | Authority |
|---|---|---|
| Any agent contract change (`.claude/agents/**`) | orchestrator | gating |
| Any security-sensitive config (secrets, tokens, auth) | security-engineer | veto |
| Any infrastructure change (Fly.io, Supabase, CI/CD) | devops | gating |
| Any schema change (`supabase/migrations/**`) | schema-architect | veto |

## Entity-specific brand notes

- Reference: **Brand_Grothouse repository** (canonical for all entities).
- G26x AI uses Cobalt `#3944BC` accent, Cool surface, Medium glow, holding archetype, 5px radius.
- Internal tooling may use relaxed brand rules but must still follow typography and color system.

## Data boundaries

- Tenant ID prefix: `g26xai`
- Data this entity may NOT access: entity-specific operational data (mortgage loans, consumer transactions, medical data)
- Data this entity exports to holding co: agent execution metrics, audit logs, portfolio health dashboards

## Stack notes

- TypeScript, Node.js
- Supabase/PostgreSQL for agent state and audit
- GitHub Actions for CI/CD and agent contract sync
- Fly.io for runtime services
- Claude Code SDK and MCP integrations

## Spend authority

- Spend that agents can draft but not authorize: < $500
- Spend that requires entity operator approval: $500 - $5,000
- Spend that requires Tony approval: > $5,000

## Special notes

- G26x AI is the meta-entity: it builds the tools that other entities use. Changes here have portfolio-wide impact.
- Agent contracts in this entity's repos are the canonical source — other entities mirror from here.
- All agent OS changes require the orchestrator agent's gating approval before merge.

---

*Last updated: 2026-05-24. Owner: Tony Grothouse. Approved by: Tony.*
