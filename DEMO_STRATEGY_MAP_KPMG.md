# Demo Strategy Map — KPMG
**Breakout Activity | Prep: 15 min | Delivery: 5–8 min**

---

## 1. Value Proposition (1–2 min)

### Customer Needs (Discovery Summary)

KPMG is deploying multi-agent AI systems to accelerate client-facing workflows — audit automation, deal advisory, regulatory analysis — where multiple specialist AI models coordinate to produce a final deliverable. Their key pain points:

- **Mean time to resolution is too long** when AI workflows fail in production — network, infrastructure, and app teams each own a slice of the stack with no unified view
- **LLM dependency risk** — their AI workflows call external LLM APIs (Azure OpenAI, Bedrock) with no visibility into whether failures are network-layer (latency, packet loss) or application-layer (auth, quota)
- **Client SLA pressure** — AI-powered advisory tools are now in client-facing delivery; downtime has reputational and contractual risk
- **Audit trail for AI behavior** — compliance requires evidence of what the AI system did, when, and why — not just that it failed
- **Shadow network issues** — Kubernetes service mesh and cloud networking failures are invisible to application monitoring alone

### Value Proposition

> "Splunk Observability Cloud, combined with ThousandEyes, gives KPMG a single answer to the most expensive question in AI operations: is this an application failure or a network failure? ThousandEyes probes each AI agent from inside the same Kubernetes cluster, on the same network paths the services use — so the moment something breaks, you know in under two minutes whether the problem is in your code, your LLM provider, or your network. Splunk APM shows you the full distributed trace across every agent call, and correlated log data — with the exact exception stack trace tied to the failing span — gives you an audit-quality RCA record with no manual correlation required."

---

## 2. Demo Mapping (2–4 min)

### The Demo Story

We use a **travel planning multi-agent AI system** as a stand-in for any KPMG AI workflow (e.g., audit document analysis with orchestrator → extraction agent → compliance agent → summary agent). Five services: orchestrator + 3 specialist agents + synthesizer. Same pattern as production AI advisory tools.

**Show in this order:**

| Step | What to show | Why |
|------|-------------|-----|
| **1. Healthy baseline** | Splunk APM service map + TE all-green dashboard | Establishes "what good looks like" — sets up the contrast |
| **2. Scenario 1: Entry point down** | Scale orchestrator to 0 → TE goes red immediately → APM shows no new traces | Maps to: *infra team takes down a pod, AI system is completely dark, who do you call first?* TE answers in 90 sec |
| **3. Scenario 2: Agent path broken** | Scale flight-agent to 0 → TE shows one test failing, five green → APM shows error on one span only | Maps to: *partial degradation — one AI capability fails silently, others keep running. TE isolates the exact broken path* |
| **4. Scenario 3: LLM auth failure** | Switch to invalid API key → TE stays fully green → APM shows errors inside agents | Maps to: *the most dangerous failure mode — the network is fine, the agents are reachable, but the LLM is rejecting calls. TE green + APM red = app config issue, not infra* |
| **5. Log correlation** | In Splunk Platform, search `index=splunk4rookies-workshop log_level=ERROR` → show `trace_id` + full stack trace | Maps to: *post-incident audit trail — exact exception, exact service, exact timestamp, correlated to the distributed trace* |

### Most Relevant Splunk Features

- **APM Service Map** — visualizes the full multi-agent call graph; errors light up immediately on the failing span
- **Distributed Traces** — full request waterfall across all 5 services; shows exactly where latency or errors originate
- **Span attributes** — `te.test.id` embedded in every `agent.call.*` span → one-click drilldown to ThousandEyes test
- **Correlated logs** — `trace_id` + `span_id` in every log record; full exception stack trace in the `body` field
- **Alerts / Detectors** — SignalFlow detectors fire within 2 minutes of degradation; alert body links directly to APM environment

### Where SPL Assistant Fits

- During log correlation step: use SPL Assistant to build the `| table _time service.name body trace_id` query live — demonstrates the natural language → search capability to a non-SPL audience
- If KPMG asks about compliance reporting: "Show me all LLM auth failures in the last 30 days by service" → SPL Assistant generates the query

### How Each Element Ties to KPMG's Needs

| Demo element | KPMG pain point addressed |
|-------------|--------------------------|
| TE inside-the-cluster probing | *Shadow network issues invisible to app monitoring* |
| TE green + APM red (Scenario 3) | *LLM dependency risk — instant app vs. network verdict* |
| APM span with `te.test.id` → TE deep link | *Cross-team MTTR — no handoff needed, one click* |
| Log `trace_id` correlation | *Audit trail for AI behavior — what failed, exactly, with evidence* |
| Detector alert linking to APM environment | *SLA pressure — proactive alerting before clients notice* |

### Confirming / Validating Customer Pain

> "Does this match the failure mode you're trying to get ahead of? When your LLM-powered workflow degrades, how long does it currently take to determine whether to call the network team or the application team?"

This question surfaces whether the primary pain is MTTR, visibility, or compliance — and lets you adjust the demo emphasis accordingly.

---

## 3. Objection Handling (1–3 min)

### Likely Objections

**Objection 1: "We already have Datadog / Dynatrace for APM."**

> Response: "ThousandEyes is the differentiator here — no other APM vendor has synthetic monitoring from inside the cluster with direct correlation to the application trace. Splunk's `te.test.id` span tag gives you a one-click path from a failing APM span to the network test that was monitoring the same path. That's not a capability Datadog builds — it's the combination that matters."
>
> *Competitor trap:* Datadog synthetics run from external PoPs, not from inside the customer's cluster. TE Enterprise Agents run on-prem, inside the pod network — they see the same routing, DNS, and firewall rules the application sees.

**Objection 2: "Our AI systems are fully managed — we use Azure OpenAI Service, Microsoft monitors it."**

> Response: "Microsoft monitors Azure OpenAI availability at the service level. They don't monitor whether *your* Kubernetes pod can reach it — that path goes through your VNet, your DNS config, your egress rules, your API key rotation. Scenario 3 shows exactly that: the Azure endpoint was up, TE confirmed it, but the auth failure was in the application config. That's a KPMG-owned problem that no cloud provider SLA covers."

**Objection 3: "Log correlation sounds useful, but we need Log Observer Connect and we don't control the Splunk admin."**

> Response: "Agreed — Log Observer Connect in the APM UI requires a service account on the Splunk Platform side, and that's a one-time admin action. But the correlation data is already there: `trace_id` is in every log record. Your team can search Splunk Platform directly with the trace ID from APM today, with no additional configuration. Log Observer Connect is the polish on top of something that already works."

### Competitor Traps

| Trap | Response |
|------|----------|
| "New Relic also does distributed tracing" | NR has no equivalent to TE inside-the-cluster synthetic monitoring. The network/app verdict is what Splunk + TE uniquely provides. |
| "We can get this from CloudWatch + X-Ray" | AWS-native tools are blind to non-AWS paths. KPMG's AI workflows call Azure OpenAI, third-party APIs, on-prem data — CloudWatch doesn't see any of it. |
| "Splunk is too expensive" | Anchor on MTTR reduction. One avoided P1 incident (war room, SLA breach, client communication) costs more than the annual license. |

---

## 4. Trusted Advisor Wrap-Up (1–2 min)

### How to Close

> "Let me summarize what we validated today. You told me your biggest risk with AI agent systems is not knowing whether a failure is a network problem or an application problem — and that the current answer involves a war room and hours of cross-team finger-pointing.
>
> What we showed is a path where that answer arrives in under two minutes, automatically, before your clients notice. ThousandEyes from inside the cluster gives you the network verdict. Splunk APM gives you the application trace. The log record gives you the stack trace with a `trace_id` that ties it all together.
>
> The pieces are already instrumented in your environment once you deploy the OTel collector — there's no secondary agent, no separate data pipeline. The correlation between network, traces, and logs happens by design.
>
> For next steps: I'd recommend a scoped proof of concept on one of your production AI workflows — not the full platform, just instrument one orchestrator-plus-agents pattern and run it for 30 days. You'll see real failure events with this level of detail. That gives you the business case data to take to procurement with actual MTTR numbers, not estimates."

### Discovery Validation Questions

- "Does the failure pattern we showed in Scenario 3 — LLM auth failure, TE fully green — match something you've actually debugged in the last 6 months?"
- "Who currently owns the bridge between your network team and your AI application team when there's an incident? Is there a runbook, or is it a phone call?"
- "If you had the `trace_id`-to-log correlation we showed, would that satisfy your compliance team's audit trail requirement for AI system behavior?"

### Proposed Next Steps

1. **30-day POC** on one production AI workflow — instrument with Splunk OTel Collector + one TE Enterprise Agent inside the cluster
2. **Workshop session** with KPMG's SRE + AI engineering teams — walk through the three failure scenarios against their actual services
3. **Log Observer Connect** enablement — schedule 30-min admin session with Splunk Platform owner to create service account and activate Related Content in APM

---

## Optional: 5-min Demo Snippet

If running the live demo, use **Scenario 3 (LLM auth failure)** — it is the most relevant to KPMG's LLM dependency risk and produces the most compelling TE vs. APM contrast (TE all green, APM errors in every agent).

```bash
# Trigger
bash scripts/09-demo-llm-unreachable.sh

# Restore
bash scripts/10-demo-restore.sh
```

**Talking points during the 5 minutes:**
1. Show TE — all 6 tests green. "The network is fine."
2. Show APM service map — errors on flight-agent, hotel-agent, activity-agent, synthesizer. "The application is not fine."
3. Click into a failing span → show LangChain error span with `AuthenticationError`
4. Open Splunk Platform → `index=splunk4rookies-workshop log_level=ERROR earliest=-5m` → show full stack trace with `trace_id`
5. "This is the audit record. This is what your compliance team needs. And it arrived without anyone touching a log file."
