← [Module 3](./03-thousandeyes-configuration.md) | Next: [Module 5 — Scenario 1: Entry Point Down](./05-scenario-entry-point-down.md) →

# Module 4: Splunk Detectors & Alerting (15 min)

## Why this matters

This is the "client SLA pressure" story: you need to know about degradation before your client does. This module builds the alerts that make Modules 5–7 proactive rather than something you have to notice by eye.

## Step 1: Inspect the detector definitions

```bash
cat scripts/05-create-splunk-detectors.sh
```

Notice each detector's alert body isn't generic — it links to the specific TE test relevant to that failure mode, and (for the LLM scenario) includes an embedded triage decision tree.

## Step 2: Create the detectors (if not already created in Module 1)

Requires an API-scoped Splunk access token (different from the ingest token used for data). Workshop EC2 instances have this pre-set as `API_TOKEN` in `/etc/environment` — `deploy.sh` and the script below pick it up automatically, no extra setup needed.

```bash
bash scripts/05-create-splunk-detectors.sh
```

If you're running outside a workshop EC2 instance and don't have `API_TOKEN` pre-set, pass your own API-scoped token instead:

```bash
SPLUNK_API_TOKEN=<your-api-scoped-token> bash scripts/05-create-splunk-detectors.sh
```

**If you see `ERROR 401: Authentication is required`:** the script fell back to an ingest-only token. Confirm `API_TOKEN` is set (`echo $API_TOKEN`) or pass `SPLUNK_API_TOKEN` explicitly.

**Want alerts emailed to you?** Set `ALERT_EMAIL` before running `deploy.sh` (or the script directly) and every detector rule is created with an Email notification recipient automatically:

```bash
ALERT_EMAIL=you@example.com bash scripts/05-create-splunk-detectors.sh
```

Without `ALERT_EMAIL`, detectors are created with no notification recipients — add them later in Splunk under Alerts → Detectors → [detector] → Edit → Notifications.

## Step 3: View them in Splunk

`https://app.us1.signalfx.com` → Alerts → Detectors → filter "Travel Planner". You should see three detectors, one per scenario:

| Detector | Fires when |
|----------|-----------|
| Scenario 1: Orchestrator Unreachable | Entry point health check fails |
| Scenario 2: Specialist Agent Unreachable | Any one specialist agent health check fails |
| Scenario 3: Agent LLM Calls Failing | LLM-layer error rate spikes while agent health checks stay green |

They're currently in a normal (green) state since nothing is broken yet.

## Step 4: Read one alert body closely

Click into "Scenario 3: Agent LLM Calls Failing" → view the alert message template. This is the payload that would page an on-call engineer. Notice it doesn't just say "something broke" — it tells them what to check next.

## Discussion Point

Compare this to how alerts are typically written — "CPU > 80%", "error rate > 5%". These detectors instead encode a **decision tree** (network healthy → check config; network degraded → check egress). What would it take to write your own alerts this way, and is that a tooling gap or a process gap on your team today?

## Troubleshooting

See repo root README → [Scripts](../README.md#scripts) for detector script reference. If detector creation fails with a 401, confirm `API_TOKEN` (or `SPLUNK_API_TOKEN`) is set and API-scoped, not just ingest scope.

---
← [Module 3](./03-thousandeyes-configuration.md) | Next: [Module 5 — Scenario 1: Entry Point Down](./05-scenario-entry-point-down.md) →
