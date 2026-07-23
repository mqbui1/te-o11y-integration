← [Module 7](./07-scenario-llm-failure.md) | Next: [Module 9 — Wrap-Up & Next Steps](./09-wrap-up.md) →

# Module 8: Log Correlation & RCA (15 min)

## Why this matters

**The audit trail story.** Compliance and post-incident review need evidence of what the AI system did, when, and why — not just "it failed." This module shows the exact exception, tied to the exact trace, with zero manual correlation.

## Step 1: Re-trigger a failure to have something to correlate

```bash
bash scripts/09-demo-llm-unreachable.sh
```

(Same as Module 7 — if you already have a recent failure, you can skip this.)

## Step 2: Watch the exception in real time

```bash
kubectl logs -n travel-planner deployment/flight-agent -f
```

You should see a full Python stack trace (`openai.AuthenticationError` or similar) — not just a one-line error message. This is because the code uses `logger.exception()`, not `logger.error()`, on every failure path (see Module 2).

## Step 3: Search Splunk Platform directly

Go to your Splunk Platform search UI (URL provided by your organizer, typically `https://<your-org>.splunkcloud.com`).

```
index=splunk4rookies-workshop log_level=ERROR earliest=-5m
| table _time service.name body trace_id
```

**What to notice:** every error event has a `trace_id`. Pick one.

## Step 4: Correlate to the trace

Copy a `trace_id` value from Step 3. Go to Splunk APM → Trace Search → paste the `trace_id`. You should land directly on the exact trace that produced that log line.

**This is the RCA record**: exact exception → exact service → exact timestamp → correlated to the full distributed trace, with no manual log-grepping across services.

## Step 5: (Optional) Related Content button

If your workshop environment has Log Observer Connect configured (ask your organizer), clicking a span in APM shows a **Related Content → Logs** button that jumps straight to the correlated log — skipping the manual `trace_id` copy/paste in Steps 3–4.

> **Caveat:** Log Observer Connect requires a Splunk Platform service account with admin-level setup. On a shared workshop Splunk Cloud instance, participants typically don't have this access — it must be configured by whoever provisioned the environment. **This does not block the RCA workflow** — the manual `trace_id` correlation in Steps 3–4 works with zero additional setup and is available to you right now.

## Discussion Point

For a compliance team asking "prove what the AI system did during this incident," is `logger.exception()` + `trace_id` correlation enough evidence today? What additional fields (user ID, request payload, model version) would you need captured for your actual audit requirements?

## Troubleshooting

See repo root README → [Log-Trace Correlation](../README.md#log-trace-correlation).

---
← [Module 7](./07-scenario-llm-failure.md) | Next: [Module 9 — Wrap-Up & Next Steps](./09-wrap-up.md) →
