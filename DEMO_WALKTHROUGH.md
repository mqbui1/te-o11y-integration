# AI Agent Monitoring Demo — Live Walkthrough

**Duration:** 25–30 minutes
**Tools:** ThousandEyes + Splunk Observability Cloud (open side by side or in separate tabs)
**Prep:** All services healthy, load generator running. Verify with `kubectl get deployments -n travel-planner` — all 5 should be `1/1`.

---

## Opening: Set the Stage

**Say:**
> "We're going to look at a problem that every team hits as soon as they start running AI agent systems in production: when something breaks, how do you know if it's a network problem or an application problem? And how fast can you answer that question?
>
> The old answer was a war room. Network team blames app team, app team blames infrastructure. With AI agents making dozens of inter-service calls per request — each one a potential failure point — that dynamic is worse than ever.
>
> Let me show you what it looks like when you instrument this properly."

---

## The Application

**Say:**
> "This is a travel planning AI system. A user sends a request — origin, destination, number of travelers — and five AI services coordinate to produce a complete itinerary.
>
> The orchestrator is the entry point. It receives the request and calls three specialist agents in parallel: a flight agent, a hotel agent, and an activity agent. A fourth service — the synthesizer — takes all three outputs and uses an LLM to produce the final itinerary.
>
> It's a classic multi-agent pattern: an orchestrator coordinating specialists, each of which calls an LLM. What we're about to break is representative of what fails in real production AI systems."

**Show:** Splunk APM → Service Map → filter env `travelplannerapp-f1b4-workshop`

> "Here's the service map in Splunk APM. Orchestrator at the center, four agents fanning out. Healthy traces flowing through every service right now — that's our load generator sending a travel plan request every two minutes."

---

## Baseline: Everything Healthy

**Show:** ThousandEyes → Test Settings → filter `travelplannerapp-f1b4`

**Say:**
> "And here's ThousandEyes. We have an Enterprise Agent running inside the same Kubernetes cluster as these services — same network, same DNS, same routing. It's probing each agent's health endpoint every two minutes. Right now everything is green: 100% availability, normal latency across all five agents and the LLM endpoint.
>
> This is our baseline. Let's break something."

---

## Scenario 1: The Entry Point Goes Dark

> **[Run in terminal: `bash scripts/07-demo-orchestrator-down.sh`]**
> *(Takes ~5 seconds. You can run this before opening the screen or while narrating.)*

**Say:**
> "A user tries to plan a trip. Nothing comes back. The entry point to the entire AI system is down. Let's see what our observability stack tells us — starting with ThousandEyes."

---

### ThousandEyes — ~2 minutes after trigger

**Show:** ThousandEyes → Test Settings → `[travelplannerapp-f1b4] Agent - Orchestrator`

**Say:**
> "ThousandEyes is the first signal. It's been probing the orchestrator every two minutes from inside the cluster. Watch the availability chart — it drops to zero. Connection refused.
>
> Now look at everything else."

**Show:** Scan the other tests — flight, hotel, activity, synthesizer, LLM

> "Every other test is green. ThousandEyes has already told us: the failure is isolated to the orchestrator. One service. Everything downstream is fine. And it detected this independently — no user complaint triggered this, no alert threshold. It's proactive, from the same network vantage the users would hit."

---

### Splunk APM — immediate

**Show:** APM → Services → `orchestrator` → `travel.plan` operation

**Say:**
> "APM confirms it from the application side. No new travel.plan traces. The orchestrator has gone dark on the service map. The load generator is still running, still sending requests — none of them are getting through.
>
> Together these two tools give us the full picture in under two minutes: orchestrator is down, everything downstream is healthy, users are completely blocked."

---

### Splunk Alert

**Show:** Alerts → Detectors → `[Travel Planner] Scenario 1: Orchestrator Unreachable`

**Say:**
> "The alert fired automatically. What's worth pointing out is what's inside the alert body — we embedded the ThousandEyes test link directly in the notification. An on-call engineer gets paged, clicks the link, and lands on the network evidence immediately. No searching, no context switching."

---

### Key Insight — Scenario 1

> "ThousandEyes detected the failure before any user complaint, before any log aggregation, on the exact same network path users would take. That's proactive monitoring for AI systems."

**[Restore: `bash scripts/10-demo-restore.sh`]** *(runs in ~60 seconds)*

---

## Scenario 2: A Specialist Agent Goes Silent

> **[Run in terminal: `bash scripts/08-demo-agent-down.sh`]**
> *(Scales flight-agent to 0 replicas. Takes ~5 seconds.)*

**Say:**
> "Different failure mode. The orchestrator is healthy — users can still reach the system. But one specialist agent, the flight agent, is down. The system keeps running: the orchestrator catches the error, substitutes fallback text, and returns a degraded response.
>
> This is the subtle failure. Error rates don't spike. Users get a response — just not a complete one. Let's see how fast we can isolate it."

---

### ThousandEyes — ~2 minutes after trigger

**Show:** ThousandEyes → Test Settings → filter prefix

**Say:**
> "ThousandEyes shows the network picture immediately. Flight Specialist test: zero availability, connection refused. Everything else — orchestrator, hotel, activity, synthesizer, the LLM — all green.
>
> The failure is isolated to one path: orchestrator to flight-agent. That's a very different problem from Scenario 1, and we know it in two minutes."

---

### Splunk APM — immediate on next request

**Show:** APM → `orchestrator` → `travel.plan` → click into a recent trace

**Say:**
> "Now the APM view. Notice the travel.plan trace completed — the orchestrator finished and returned a response. But look inside the trace."

**Show:** Expand the trace — `agent.call.flight-agent` span shows ERROR, others are green

> "agent.call.flight-agent: ERROR. Connection refused. But hotel, activity, and synthesizer — all healthy green spans. The orchestrator handled the failure gracefully, substituted fallback content, and kept going.
>
> Now watch this."

**Show:** Click `agent.call.flight-agent` span → Tags panel → click `te.test.id` → "View in ThousandEyes" button appears

**Say:**
> "On this span, we embedded the ThousandEyes test ID for the flight-agent network path. When I click it, Splunk renders a 'View in ThousandEyes' button — one click from a failing APM span to the network evidence. The link was in the trace at the moment the request was processed. No searching, no copy-pasting test IDs."

**Show:** Click "View in ThousandEyes" → lands on the failing flight-agent test

---

### Splunk Alert

**Show:** Alerts → `[Travel Planner] Scenario 2: Specialist Agent Unreachable`

**Say:**
> "The alert fired specifically for flight-agent — not a generic 'something is wrong' alert. It links directly to the flight-agent TE test. Hotel, activity, and synthesizer don't alert — they're healthy. The alert is as precise as the failure."

---

### Key Insight — Scenario 2

> "One click from a failing APM span to the network evidence in ThousandEyes. The link is embedded in the trace — it's there on every agent call, automatically, from the moment the system deployed. And TE confirms the other three agent paths are completely healthy, so we know exactly where to look."

**[Restore: `bash scripts/10-demo-restore.sh`]**

---

## Scenario 3: The LLM Problem

> **[Run in terminal: `bash scripts/09-demo-llm-unreachable.sh`]**
> *(Reconfigures agents with an invalid API key and immediately fires a test request. Takes ~60 seconds.)*

**Say:**
> "This is the most interesting scenario for AI systems specifically, and the most common failure mode we see in production.
>
> Every agent is running. Every health check passes. The orchestrator can reach every specialist. But every agent that tries to call the LLM is failing.
>
> First question any team asks: is this a network problem? Is something blocking egress to the LLM provider?"

---

### ThousandEyes — immediate

**Show:** ThousandEyes → Test Settings → all tests

**Say:**
> "Look at ThousandEyes. All five agent health tests: green — agents are up and responding. The LLM test, which probes the OpenAI status page from inside this cluster: also green. The network path from this cluster to the LLM provider is healthy.
>
> That single observation just saved your team potentially hours of investigation. This is off the network team's plate. Definitively, immediately, before anyone opened a log file."

---

### Splunk APM — immediate

**Show:** APM → `flight-agent` → `POST /invoke` → recent error traces

**Say:**
> "APM tells the rest of the story. The agent.call spans from the orchestrator all succeeded — agents received the requests. But inside each agent, the LangChain span errors out."

**Show:** Click into the error trace → expand the exception details

> "The exception: AuthenticationError. Invalid API key. The same error appears in hotel-agent, activity-agent, and synthesizer — all four failing simultaneously.
>
> Diagnosis: application configuration issue. Not a network problem, not an infrastructure problem. A misconfigured credential. That's a ten-second fix once you know what it is.
>
> Without ThousandEyes giving you the green network signal first — how long does your team spend checking firewall rules, egress policies, DNS resolution before someone thinks to look at the API key?"

---

### Splunk Alert

**Show:** Alerts → `[Travel Planner] Scenario 3: Agent LLM Calls Failing`

**Say:**
> "The alert body includes the LLM reachability test link and a built-in triage guide: if TE shows network healthy, check your config — base URL, API key, provider settings. If TE shows network degraded, investigate egress routing. The decision tree is embedded in the alert itself."

---

### Key Insight — Scenario 3

> "For AI systems, the LLM is a shared dependency across every agent. When it breaks, everything degrades simultaneously and it looks catastrophic. ThousandEyes separates 'can we reach the LLM network' from 'can our app authenticate with the LLM API' — and that separation is the difference between a five-minute fix and a two-hour war room."

**[Restore: `bash scripts/10-demo-restore.sh`]**

---

## Closing: The Pattern

**Say:**
> "Three failure modes, three different root causes — entry point down, agent-to-agent path broken, LLM auth failure. In each case, ThousandEyes gave us the network layer answer in under two minutes, from inside the cluster, on the same paths the application uses.
>
> The pattern is always the same: APM shows you what failed in the application, ThousandEyes tells you whether the network caused it. Together, they turn hours of cross-team investigation into a single-click answer.
>
> For AI agent systems — where a single user request touches five services, any of which might be calling an external LLM — that speed matters. You're not just debugging software. You're debugging a system that your users expect to reason, adapt, and respond in real time."

---

## Log-Trace Correlation — If Asked

All five services emit structured logs with `trace_id` and `span_id` automatically injected by the OTel SDK. During any failure scenario, error logs include the full exception stack trace.

**Search in Splunk Platform** (`https://o11y-workshop-amer.splunkcloud.com`):
```
index=splunk4rookies-workshop log_level=ERROR earliest=-5m
| table _time service.name body trace_id
```

Copy a `trace_id` from a log → paste into Splunk APM trace search to jump directly to the failing trace, or click **Related Content → Logs** in APM (requires Log Observer Connect).

**Log Observer Connect caveat:** Requires a Splunk Platform service account (admin access to `o11y-workshop-amer.splunkcloud.com`). The shared workshop Splunk Cloud instance is managed by the workshop organizer — participants typically cannot create service accounts. Contact whoever provisioned the workshop to enable the APM → Logs Related Content button.

---

## Business Value — If Asked

| The old way | With this stack |
|------------|-----------------|
| Network vs. app blame game | TE green/red gives an instant, definitive answer |
| Hours to isolate which agent failed | TE pinpoints the exact path in 2 minutes |
| LLM failure requires log diving across 4 services | TE confirms network health before you open a log |
| Manual correlation between monitoring tools | `te.test.id` embedded in every APM span — one click |
| Reactive alerting after user complaints | TE detects failures proactively from inside the cluster |
| Generic alerts with no triage guidance | Alerts link directly to the relevant TE test + decision tree |
| No RCA evidence after incident | Full exception stack traces in logs, correlated to APM trace by `trace_id` |

---

## Demo Commands (Presenter Reference)

| Action | Command |
|--------|---------|
| Scenario 1 — orchestrator down | `bash scripts/07-demo-orchestrator-down.sh` |
| Scenario 2 — flight-agent down | `bash scripts/08-demo-agent-down.sh` |
| Scenario 3 — LLM auth failure | `bash scripts/09-demo-llm-unreachable.sh` |
| Restore everything | `bash scripts/10-demo-restore.sh` |

| Tool | Where to go |
|------|-------------|
| Splunk APM | `https://app.us1.signalfx.com` → APM → env: `travelplannerapp-f1b4-workshop` |
| ThousandEyes | `https://app.thousandeyes.com` → Test Settings → filter `travelplannerapp-f1b4` |
| Splunk Alerts | `https://app.us1.signalfx.com` → Alerts → Detectors → filter `Travel Planner` |
| Splunk Platform logs | `https://o11y-workshop-amer.splunkcloud.com` → Search: `index=splunk4rookies-workshop log_level=ERROR earliest=-5m` |
