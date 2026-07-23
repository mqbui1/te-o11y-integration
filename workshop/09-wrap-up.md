← [Module 8](./08-log-correlation-rca.md) | [Back to Agenda](./AGENDA.md)

# Module 9: Wrap-Up & Next Steps (10 min)

## What you did today

| Module | You proved |
|--------|-----------|
| 1–4 | This entire pipeline deploys with one collector, no secondary agents, and every signal (traces, TE tests, alerts) is inspectable and self-owned |
| 5 | Total outage triage — network vs. app verdict in under 2 minutes |
| 6 | Partial degradation isolation — one click from a failing span to network evidence |
| 7 | The highest-risk AI-specific failure mode (LLM auth failure) — TE rules out network before you open a log |
| 8 | Post-incident RCA — exact exception, correlated to trace, with no admin access required |

## Teardown (if this is a shared/temporary environment)

```bash
./teardown.sh
```

## Discussion: turning this into a business case

- Which of the three scenarios matched a failure mode you've actually debugged in the last 6 months?
- Who currently owns the handoff between your network team and your AI application team during an incident — is there a runbook, or is it a phone call?
- If you had the `trace_id`-to-log correlation from Module 8 today, would it satisfy your compliance team's audit requirement for AI system behavior?

## Proposed next steps

1. **Scoped POC** — instrument one of your actual production AI workflows (not this travel planner) with the same OTel Collector + one TE Enterprise Agent inside your cluster. Run it for 30 days to collect real failure-event data.
2. **Pattern port** — take the logging pattern from Module 2 (`LoggingHandler` bridge + `logger.exception()` discipline) and apply it to one of your own services this week — it's a small, low-risk change.
3. **Log Observer Connect enablement** — if Module 8's manual correlation was useful but you want the one-click Related Content button, this requires a short admin session with whoever owns your Splunk Platform instance.

## Feedback

If anything in this workshop didn't match what you expected to see, or a module's commands didn't produce the described result, that's useful signal — flag it to your workshop organizer.

---
← [Module 8](./08-log-correlation-rca.md) | [Back to Agenda](./AGENDA.md)
