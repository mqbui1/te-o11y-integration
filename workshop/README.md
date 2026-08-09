# Self-Guided Workshop — AI Agent Observability with ThousandEyes + Splunk

This is a hands-on version of the travel-planner AI agent demo in the repo root. Instead of watching a presenter run it, you deploy, break, and observe it yourself.

**Start here:** [`AGENDA.md`](./AGENDA.md) — full module breakdown with time estimates and what each module proves.

**Planning attendance?** See [`ROLES.md`](./ROLES.md) — which roles should attend which modules, and suggested attendance patterns if you can't get everyone in the room for the full session.

## What you're working with

The same 5-service AI multi-agent travel planner used in the live demo (`../travel-planner/`), deployed via the same scripts (`../scripts/`). This workshop doesn't duplicate that logic — every module tells you exactly which existing script to run and what to look for in the output.

```
orchestrator  POST /plan
  ├── flight-agent    — flight search specialist
  ├── hotel-agent     — hotel recommendation specialist
  ├── activity-agent  — activities curation specialist
  └── synthesizer     — combines results into itinerary
```

## Before you start

1. **Confirm access** — you should have:
   - SSH access to your assigned EC2 instance
   - `TE_BEARER_TOKEN` (ThousandEyes OAuth Bearer Token — Account Settings → User API Tokens → OAuth Bearer Token tab)
   - Splunk Observability Cloud login for viewing APM (`https://app.us1.signalfx.com`)
2. **Pick a unique identifier** — set `AGENT_HOSTNAME` and `TEST_PREFIX` to something identifying you (e.g. your name or initials) so your TE tests and agent don't collide with other participants sharing the same TE account.
3. **Read the repo root [`README.md`](../README.md)** once for architecture context — the workshop assumes you've seen the diagram and service list there.

## Workshop modules

| Module | File |
|--------|------|
| 1. Environment & Architecture | [`01-environment-setup.md`](./01-environment-setup.md) |
| 2. OTel Instrumentation Deep-Dive | [`02-instrumentation-deep-dive.md`](./02-instrumentation-deep-dive.md) |
| 3. ThousandEyes Configuration | [`03-thousandeyes-configuration.md`](./03-thousandeyes-configuration.md) |
| 4. Splunk Detectors & Alerting | [`04-splunk-detectors-and-alerts.md`](./04-splunk-detectors-and-alerts.md) |
| 5. Scenario 1: Entry Point Down | [`05-scenario-entry-point-down.md`](./05-scenario-entry-point-down.md) |
| 6. Scenario 2: Agent Path Broken | [`06-scenario-agent-path-broken.md`](./06-scenario-agent-path-broken.md) |
| 7. Scenario 3: LLM Auth Failure | [`07-scenario-llm-failure.md`](./07-scenario-llm-failure.md) |
| 8. Wrap-Up & Next Steps | [`08-wrap-up.md`](./08-wrap-up.md) |

## Getting help during the workshop

Every module has a **Troubleshooting** section at the bottom pointing back to the relevant section of the repo root [`README.md`](../README.md#troubleshooting), which has the deeper reference material (token formats, common pod failures, etc).

## Known limitation: log correlation / Splunk Platform

This workshop's shared environment doesn't include a Splunk Platform (Splunk Cloud) instance for participants to search logs in directly, so the standalone log-search / RCA exercise isn't part of this run. The underlying pattern — structured logs auto-tagged with `trace_id`/`span_id`, full exception stack traces via `logger.exception()` — is still visible in code and in `kubectl logs` output during Module 2 and every failure scenario. Log Observer Connect (the APM → Logs "Related Content" button) also requires Splunk Platform admin access and is out of scope for the same reason. See the note in [`08-wrap-up.md`](./08-wrap-up.md).
