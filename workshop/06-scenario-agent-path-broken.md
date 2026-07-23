← [Module 5](./05-scenario-entry-point-down.md) | Next: [Module 7 — Scenario 3: LLM Auth Failure](./07-scenario-llm-failure.md) →

# Module 6: Scenario 2 — Agent Path Broken (15 min)

## Why this matters

**The question this answers:** one AI capability silently fails while the rest of the system keeps running and returning "successful" (but degraded) responses to users. This is the failure mode that error-rate dashboards miss — the overall request still completes.

## Step 1: Break it

```bash
bash scripts/08-demo-agent-down.sh
# or target a specific agent:
AGENT=hotel-agent bash scripts/08-demo-agent-down.sh
```

Scales the target specialist agent to 0 replicas.

## Step 2: Check ThousandEyes (wait ~2 minutes)

`https://app.thousandeyes.com` → the specialist's health test (e.g. `Agent - Flight Specialist`).

**What you should see:** that one test → 0% availability. **Every other agent test and the LLM test stay green.** The failure is proven to be isolated to one orchestrator-to-agent path.

## Step 3: Check Splunk APM — this is the important part

`https://app.us1.signalfx.com` → APM → `orchestrator` → `travel.plan` → open a recent trace.

**What you should see:** the trace **completes** (the orchestrator caught the error and returned a degraded response). Inside it, `agent.call.flight-agent` → ERROR span, while the other agent-call spans and the synthesizer are green.

## Step 4: Use the drilldown

Click the failing span → Tags panel → click `te.test.id` → **"View in ThousandEyes"** button should appear (requires the Global Data Link from Module 3 — if it's missing, this is your cue to set it up now).

## Step 5: Check the alert

"Scenario 2: Specialist Agent Unreachable" — should be firing specifically for the agent you broke, not a generic alert. Hotel/activity/synthesizer alerts should NOT be firing.

## The verdict

One click from a failing span to network-layer evidence. No manual copy-paste of test IDs, no cross-tool context switching.

## Step 6: Restore

```bash
bash scripts/10-demo-restore.sh
```

## Discussion Point

This scenario doesn't spike your error rate — the orchestrator handles it gracefully. If your current alerting is purely threshold-based (error rate, latency), would this failure mode even trigger a page in your environment today?

## Troubleshooting

See repo root README → [Demo Scenarios: Scenario 2](../README.md#scenario-2-agent-to-agent-communication-failure) and ["View in ThousandEyes" button not appearing](../README.md#view-in-thousandeyes-button-not-appearing).

---
← [Module 5](./05-scenario-entry-point-down.md) | Next: [Module 7 — Scenario 3: LLM Auth Failure](./07-scenario-llm-failure.md) →
