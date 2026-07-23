# Workshop Agenda — AI Agent Observability with ThousandEyes + Splunk

**Format:** Hands-on, self-guided. Each module = short concept intro + something you deploy/break/observe yourself.
**Audience:** SRE, platform engineering, AI/ML engineering teams operating (or planning to operate) multi-agent AI systems in production.
**Total time:** ~2h45m (can be split across two sessions, or trimmed — see "If you only have 90 minutes" below)

Every module below maps to a specific operational pain point. The point of the workshop isn't the tooling — it's proving, on your own keyboard, that you can answer "network or app?" in under two minutes, and that you have an audit trail when the answer matters.

---

## At a Glance

| # | Module | Time | Topic | Value Shown |
|---|--------|------|-------|-------------|
| 0 | [Welcome & Objectives](#module-0--welcome--objectives-5-min) | 5 min | Why this workshop, what you'll leave with | Sets expectations |
| 1 | [Environment & Architecture](./01-environment-setup.md) | 20 min | Deploy the stack, understand the moving parts | Deployment footprint — no secondary agent, one collector |
| 2 | [OTel Instrumentation Deep-Dive](./02-instrumentation-deep-dive.md) | 30 min | How traces, spans, and logs get generated in code | Nothing is a black box — you own the instrumentation |
| 3 | [ThousandEyes Configuration](./03-thousandeyes-configuration.md) | 20 min | Deploy TE agent, create in-cluster synthetic tests | Shadow network issues — visibility app monitoring alone can't give you |
| 4 | [Splunk Detectors & Alerting](./04-splunk-detectors-and-alerts.md) | 15 min | Build proactive alerts with embedded triage links | SLA pressure — catch it before the client does |
| 5 | [Scenario 1: Entry Point Down](./05-scenario-entry-point-down.md) | 15 min | Break the orchestrator, triage with TE + APM | MTTR — who do you call first? |
| 6 | [Scenario 2: Agent Path Broken](./06-scenario-agent-path-broken.md) | 15 min | Break one specialist agent, isolate the failure | Partial degradation is the hardest to catch — TE isolates it in one test |
| 7 | [Scenario 3: LLM Auth Failure](./07-scenario-llm-failure.md) | 20 min | Break the LLM call, prove it's not the network | LLM dependency risk — the #1 most expensive triage question in AI ops |
| 8 | [Log Correlation & RCA](./08-log-correlation-rca.md) | 15 min | Pull the exact exception tied to a trace_id | Audit trail — evidence of what the AI system did, when, why |
| 9 | [Wrap-Up & Next Steps](./09-wrap-up.md) | 10 min | Teardown, discussion, POC scoping | Turn today into a business case |

---

## Module 0 — Welcome & Objectives (5 min)

**What we're solving:** When your AI agent workflow fails in production, the single most expensive question is *"is this a network failure or an application failure?"* — because the answer determines which team gets paged, and getting it wrong costs hours.

**What you'll leave with:**
- A running 5-service AI multi-agent system, fully instrumented, on your own infrastructure
- Hands-on experience triaging 3 realistic failure modes using ThousandEyes + Splunk APM together
- A working log-to-trace correlation pattern you can lift directly into your own services
- A clear view of what it takes to stand this up in your own environment (not just watch someone else do it)

**How to use this workshop:** Each module is a markdown file with commands to run and things to look for. Run the commands yourself — don't just read them. If something doesn't match what's described, that's a great discussion point, not a failure.

---

## Module Sequence Rationale

The modules build in a deliberate order:

1. **Setup → Instrumentation → TE config → Alerting** (Modules 1–4) establishes the full observability pipeline *before* anything breaks — so when you see a scenario later, you already understand every signal you're looking at, not just following a script.
2. **Three failure scenarios** (Modules 5–7) go from simplest to most nuanced: total outage → partial degradation → the dangerous "everything looks healthy but isn't" case. This mirrors how failure complexity actually escalates in production.
3. **Log correlation** (Module 8) comes last among the technical modules because by then you've generated real error traces to correlate against — it's not abstract.
4. **Wrap-up** (Module 9) is deliberately short and discussion-driven — the goal is to turn the hands-on experience into a decision about next steps, not another lecture.

---

## If You Only Have 90 Minutes

Run: **Module 1** (setup, 20 min) → **Module 7** (LLM failure scenario, 20 min — the highest-value scenario for AI-specific risk) → **Module 8** (log correlation, 15 min) → **Module 9** (wrap-up, 10 min). Skip Modules 2–6 and read them afterward as reference.

## Prerequisites

- SSH access to your assigned EC2 instance (provided by workshop organizer)
- `kubectl` access to the k3d cluster on that instance
- A ThousandEyes account with an OAuth Bearer Token (Account Settings → User API Tokens)
- Splunk Observability Cloud access to view APM (credentials provided by workshop organizer)

See [`README.md`](./README.md) for the full setup checklist before starting Module 1.
