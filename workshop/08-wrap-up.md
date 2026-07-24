← [Module 7](./07-scenario-llm-failure.md) | [Back to Agenda](./AGENDA.md)

# Module 8: Wrap-Up & Next Steps (10 min)

## What you did today

| Module | You proved |
|--------|-----------|
| 1–4 | This entire pipeline deploys with one collector, no secondary agents, and every signal (traces, TE tests, alerts) is inspectable and self-owned |
| 5 | Total outage triage — network vs. app verdict in under 2 minutes |
| 6 | Partial degradation isolation — one click from a failing span to network evidence |
| 7 | The highest-risk AI-specific failure mode (LLM auth failure) — TE rules out network before you open a log |

> **Note on log-trace correlation:** the underlying pattern (structured logs auto-tagged with `trace_id`/`span_id`, full exception stack traces via `logger.exception()`) is already live in every service you deployed today — you saw it in Module 2. This workshop's shared environment doesn't include a Splunk Platform (Splunk Cloud) instance for participants to search logs in directly, so that exercise isn't part of today's run. Ask your organizer if a working example is available to see it end-to-end.

## Teardown (if this is a shared/temporary environment)

```bash
./teardown.sh
```

## Discussion: turning this into a business case

- Which of the three scenarios matched a failure mode you've actually debugged in the last 6 months?
- Who currently owns the handoff between your network team and your AI application team during an incident — is there a runbook, or is it a phone call?
- If every log line from your AI agents were automatically tagged with a `trace_id` today, would that satisfy your compliance team's audit requirement for AI system behavior?

## Proposed next steps

1. **Scoped POC** — instrument one of your actual production AI workflows (not this travel planner) with the same OTel Collector + one TE Enterprise Agent inside your cluster. Run it for 30 days to collect real failure-event data.
2. **Pattern port** — take the logging pattern from Module 2 (`LoggingHandler` bridge + `logger.exception()` discipline) and apply it to one of your own services this week — it's a small, low-risk change.
3. **Log correlation walkthrough** — schedule a follow-up session against a Splunk Platform instance you control to see trace-to-log correlation and Log Observer Connect end-to-end.

## Feedback

If anything in this workshop didn't match what you expected to see, or a module's commands didn't produce the described result, that's useful signal — flag it to your workshop organizer.

---
← [Module 7](./07-scenario-llm-failure.md) | [Back to Agenda](./AGENDA.md)
