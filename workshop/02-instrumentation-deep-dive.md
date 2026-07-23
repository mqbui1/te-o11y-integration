← [Module 1](./01-environment-setup.md) | Next: [Module 3 — ThousandEyes Configuration](./03-thousandeyes-configuration.md) →

# Module 2: OTel Instrumentation Deep-Dive (30 min)

## Why this matters

Everything you'll see in APM and Splunk Platform logs for the rest of this workshop comes from code you can read right now, in this repo. There's no proprietary agent doing magic — it's the OpenTelemetry SDK, wired up the same way you'd wire it into your own AI services.

**Value to keep in mind:** this is the "audit trail" story — every span and log line is something you configured, not a vendor black box. That matters when a compliance team asks "how do we know what the AI system actually did?"

## Step 1: Read the shared OTel setup

```bash
cat travel-planner/shared/otel_setup.py
```

Find and understand three things:
- **Trace export**: `TracerProvider` + `BatchSpanProcessor` + `OTLPSpanExporter` — standard OTel, nothing custom
- **B3 propagation**: `CompositePropagator` with `B3Format` — this is what lets ThousandEyes' synthetic requests appear as root spans inside your traces (more in Module 3)
- **Log bridge**: `LoggingHandler` attached to Python's standard `logging` module — this is what auto-injects `trace_id`/`span_id` into every log line without any code change at the call site

## Step 2: Read one service end-to-end

```bash
cat travel-planner/orchestrator/app.py
```

Trace the request lifecycle:
1. `POST /plan` received
2. `logger.info("travel.plan started...")` — first log line, already tagged with trace context
3. `_call_agent()` calls each specialist — note the `try/except` with `logger.exception()` on failure, not `logger.error()`. This is deliberate: `.exception()` captures the full stack trace in the log body; `.error()` only logs the string representation. For RCA, you want the former.
4. `span.set_attribute("te.correlation", ...)` on failure — this is what links an APM error span back to the relevant TE test (see Module 3)

## Step 3: Compare a specialist agent

```bash
cat travel-planner/flight_agent/app.py
```

Same pattern, simpler: `/health` endpoint calls `stamp_te_span()` (tags the span with `te.test.id` when a TE probe hits it), `/invoke` does the actual work with the same logging discipline.

## Step 4: Watch it happen live

```bash
kubectl logs -n travel-planner deployment/orchestrator -f
```

In another terminal, fire a request (same command as Module 1, Step 4). Watch the log lines stream — each one already has structure, even though this is just `logging.getLogger(__name__).info(...)` in Python. No manual trace_id plumbing anywhere in the application code.

## Step 5: Confirm the log pipeline

```bash
kubectl logs -l app=splunk-otel-collector -f --container otel-collector
```

Fire another request. You should see log records flowing through the collector's logs pipeline (`otlp` receiver → `splunk_hec/platform_logs` exporter). This is the same collector handling traces and metrics — one pipeline, three signal types.

## Discussion Point

The logging pattern here (`logger.exception()` on every failure path, `LoggingHandler` bridge, no manual trace_id injection) is copy-pasteable into any Python service. What would it take to add this pattern to one of your own AI agent services? Is the blocker technical, or is it "nobody's owned doing this yet"?

## Troubleshooting

See repo root README → [Log-Trace Correlation](../README.md#log-trace-correlation) and [Bi-directional Drilldowns Setup](../README.md#bi-directional-drilldowns-setup).

---
← [Module 1](./01-environment-setup.md) | Next: [Module 3 — ThousandEyes Configuration](./03-thousandeyes-configuration.md) →
