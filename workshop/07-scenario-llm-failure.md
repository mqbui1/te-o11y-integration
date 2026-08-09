← [Module 6](./06-scenario-agent-path-broken.md) | Next: [Module 8 — Wrap-Up & Next Steps](./08-wrap-up.md) →

# Module 7: Scenario 3 — LLM Auth Failure (20 min)

## Why this matters

**This is the highest-value scenario in the workshop.** It answers the most dangerous, most common failure mode in production AI systems: every agent is reachable, every health check passes, but every LLM call is failing. Is it a network problem? If your team doesn't know the answer in under a minute, you're burning hours checking firewall rules and egress policies for a problem that's actually a misconfigured API key.

## Step 1: Break it

```bash
bash scripts/09-demo-llm-unreachable.sh
```

This reconfigures the agents with an invalid LLM API key and fires a test request. Takes ~60 seconds.

## Step 2: Check ThousandEyes — this is the key signal

```bash
bash scripts/check-te-status.sh
```

**What you should see:** all 5 agent health tests → **`UP`**. The `LLM - OpenAI Status` test → **also `UP`**. The network path from this cluster to the LLM provider is fully healthy.

**Stop and let this land**: this single observation rules out network/infra/egress as the cause, definitively, before anyone opens a log file.

## Step 3: Check Splunk APM

`https://app.us1.signalfx.com` → APM → `flight-agent` → `POST /invoke` → open a recent error trace.

**What you should see:** the `agent.call.*` spans from the orchestrator all succeeded (agents received the requests fine). But the LangChain span **inside** each agent errors out with `AuthenticationError`. All four downstream services fail the same way simultaneously — this is what makes it look catastrophic at first glance.

## Step 4: Diagnose

Network: healthy (confirmed by TE). Application: misconfigured credential (confirmed by APM). This is a config fix, not an infrastructure investigation.

## Step 5: Check the alert

"Scenario 3: Agent LLM Calls Failing" — open the alert body. Notice the embedded decision tree: *if TE shows network healthy, check your app config (API key, base URL, provider settings); if TE shows network degraded, investigate egress routing.*

If you set `ALERT_EMAIL` in Module 1, check your inbox — the same decision tree should show up in the email body.

## The verdict

TE separates "can we reach the LLM network" from "can our app authenticate with the LLM API." That separation is the difference between a 5-minute fix and a 2-hour war room where the network team gets paged for nothing.

## Step 6: Restore

```bash
bash scripts/10-demo-restore.sh
```

## Discussion Point

Think about your own AI workflows that call Azure OpenAI, Bedrock, or a third-party LLM API. If every one of those calls started failing right now, would your current monitoring tell you within a minute whether it's your network or your app? What would that investigation actually look like today?

## Troubleshooting

See repo root README → [Demo Scenarios: Scenario 3](../README.md#scenario-3-agent-to-llm-communication-failure).

---
← [Module 6](./06-scenario-agent-path-broken.md) | Next: [Module 8 — Wrap-Up & Next Steps](./08-wrap-up.md) →
