← [Module 4](./04-splunk-detectors-and-alerts.md) | Next: [Module 6 — Scenario 2: Agent Path Broken](./06-scenario-agent-path-broken.md) →

# Module 5: Scenario 1 — Entry Point Down (15 min)

## Why this matters

**The question this answers:** infra takes down a pod, the entire AI system goes dark. Who do you call first — network or app team? This is the simplest failure mode, and it's your baseline for how fast triage should be for everything more subtle later.

## Step 1: Break it

```bash
bash scripts/07-demo-orchestrator-down.sh
```

This scales `orchestrator` to 0 replicas. Takes ~5 seconds.

## Step 2: Check ThousandEyes (wait ~2 minutes for the next probe cycle)

```bash
bash scripts/check-te-status.sh --watch
```

**What you should see:** `Agent - Orchestrator` flips to `DOWN` (connection refused). **All other tests remain `UP`** — flight, hotel, activity, synthesizer, LLM. Leave `--watch` running; it refreshes every 15s. (No UI login needed — this reads the same data straight from the TE API using your `TE_BEARER_TOKEN`.)

## Step 3: Check Splunk APM

`https://app.us1.signalfx.com` → APM → `orchestrator` service.

**What you should see:** no new `travel.plan` traces. The orchestrator goes dark on the service map.

## Step 4: Check the alert

Alerts → Detectors → "Scenario 1: Orchestrator Unreachable" — should have fired within ~2 minutes. Open the alert body and confirm it links to the ThousandEyes test.

If you set `ALERT_EMAIL` in Module 1, check your inbox — you should have an email for this alert too, with the same triage body.

## The verdict

TE isolated the failure to exactly one service, independently, before any user complaint. APM confirms zero traffic is getting through. **Time to answer "who do I call": under 2 minutes, no war room.**

## Step 5: Restore

```bash
bash scripts/10-demo-restore.sh
```

Wait ~2 minutes for TE tests to return to green before moving to the next module.

## Discussion Point

This is the easy case — total outage, obvious symptom. In your environment, how long does an equivalent full-outage scenario currently take to diagnose? Is the gap tooling, or process (who gets paged, who has access to which dashboard)?

## Troubleshooting

See repo root README → [Demo Scenarios: Scenario 1](../README.md#scenario-1-orchestrator-unreachable).

---
← [Module 4](./04-splunk-detectors-and-alerts.md) | Next: [Module 6 — Scenario 2: Agent Path Broken](./06-scenario-agent-path-broken.md) →
