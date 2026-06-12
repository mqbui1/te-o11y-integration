# ThousandEyes + Splunk Observability — AI Agent Monitoring Demo Script

**Audience:** Customer-facing technical demo
**Duration:** ~30–45 minutes for all three scenarios
**Purpose:** Show how ThousandEyes and Splunk APM together provide instant root cause clarity when AI agent systems fail — separating network problems from application problems in seconds.

---

## The Problem This Solves

AI multi-agent systems introduce a new class of failure: when an orchestrator calls a downstream agent and something goes wrong, you face an immediate question — **is this a network problem or an application problem?**

Traditional APM tells you a span failed. It doesn't tell you whether the network between two services is healthy. ThousandEyes fills that gap. Together, they collapse what used to be a war room into a single-click answer.

---

## The Application: AI Travel Planner

The demo application is a **5-service AI travel planning system** built with Python Flask and deployed on Kubernetes. A user submits a travel request, and the system coordinates multiple specialist AI agents to produce a complete itinerary.

### Service Architecture

```
User → POST /plan
         │
         ▼
    orchestrator          ← entry point, coordinates all agents
         │
         ├──→ flight-agent      ← finds best flight option
         ├──→ hotel-agent       ← recommends hotels
         ├──→ activity-agent    ← curates local experiences
         └──→ synthesizer       ← combines results into final itinerary
                  │
                  ▼
         [LLM: OpenAI / Bedrock / Mock]
```

### What Each Service Does

| Service | Role | Endpoint |
|---------|------|----------|
| **orchestrator** | Receives user travel requests, calls each specialist in sequence, returns final itinerary | `POST /plan` |
| **flight-agent** | Searches for flight options based on origin, destination, and departure date | `POST /invoke` |
| **hotel-agent** | Recommends hotels based on destination and dates | `POST /invoke` |
| **activity-agent** | Curates local experiences and highlights for the destination | `POST /invoke` |
| **synthesizer** | Takes all specialist outputs and uses the LLM to produce a polished travel itinerary | `POST /invoke` |

### How a Request Flows

1. User (or load generator) sends `POST /plan` to the orchestrator with `origin`, `destination`, and `travellers`
2. Orchestrator calls flight-agent, hotel-agent, and activity-agent in sequence — each has a **30-second timeout**
3. Each specialist calls the LLM to format its response
4. Orchestrator calls synthesizer with all three results
5. Synthesizer uses the LLM to combine everything into a complete itinerary
6. Orchestrator returns the full travel plan to the user

In **mock mode** (demo default), agents return pre-built responses without calling a real LLM — all HTTP paths are exercised without requiring API keys.

---

## The Load Generator

A Kubernetes **CronJob** runs every 2 minutes and continuously sends travel plan requests to the orchestrator. Each job runs for approximately 2.5 minutes, so there is always active traffic flowing through the system.

**What it sends:**
```json
POST /plan
{
  "origin": "Seattle",
  "destination": "Paris",
  "travellers": 2
}
```

This ensures Splunk APM always has fresh traces and ThousandEyes always has a baseline to compare against. When something breaks, the load generator immediately exposes the failure in both tools without requiring manual trigger.

---

## ThousandEyes Test Setup

ThousandEyes runs an **Enterprise Agent co-located inside the Kubernetes cluster** (`te-agent-petclinictesting-ecb9`). Because the agent is on the same network as the travel planner services, its measurements reflect the exact same network path the orchestrator uses when calling downstream agents.

### Tests Configured

| Test Name | Target | What It Proves |
|-----------|--------|----------------|
| `[prefix] Agent - Orchestrator` | `http://orchestrator.travel-planner.svc.cluster.local/health` | Entry point reachability |
| `[prefix] Agent - Flight Specialist` | `http://flight-agent.travel-planner.svc.cluster.local/health` | Orchestrator → flight-agent network path |
| `[prefix] Agent - Hotel Specialist` | `http://hotel-agent.travel-planner.svc.cluster.local/health` | Orchestrator → hotel-agent network path |
| `[prefix] Agent - Activity Specialist` | `http://activity-agent.travel-planner.svc.cluster.local/health` | Orchestrator → activity-agent network path |
| `[prefix] Agent - Synthesizer` | `http://synthesizer.travel-planner.svc.cluster.local/health` | Orchestrator → synthesizer network path |
| `[prefix] LLM - OpenAI Status` | `https://status.openai.com` | Network path from cluster to LLM provider |

**All 5 agent health tests run every 2 minutes with distributed tracing enabled.** ThousandEyes injects B3 trace headers into each request, so every health check appears as a root span in Splunk APM — tagged with the ThousandEyes test name and ID. This creates the TE → APM drilldown direction.

The **LLM test** targets `https://status.openai.com` (a public endpoint that returns 200) to validate that the cluster has a healthy network path to the LLM provider, independent of application-layer authentication.

### Bi-Directional Drilldowns

**APM → ThousandEyes:**
Every `agent.call.*` span generated by the orchestrator is tagged with `te.test.id`, `te.test.name`, and `te.test.url` — the ThousandEyes test that monitors that exact network path. In Splunk APM, clicking the `te.test.id` attribute on a failing span reveals a **"View in ThousandEyes"** button that opens the test result directly.

**ThousandEyes → APM:**
Because distributed tracing is enabled on all agent health tests, each TE-initiated request propagates a trace ID through the application. The `/health` endpoint stamps the span with `te.test.id` and `te.test.name`, making TE-originated requests traceable in APM alongside real user traffic.

---

## Pre-Demo Health Check

Before starting, verify everything is green:

```bash
# All pods running
kubectl get deployments -n travel-planner

# Expected output:
# NAME             READY
# activity-agent   1/1
# flight-agent     1/1
# hotel-agent      1/1
# orchestrator     1/1
# synthesizer      1/1
```

**In ThousandEyes:** All 6 tests should show 100% availability.
**In Splunk APM:** `orchestrator` service should show steady `travel.plan` traces with no errors.

**Reset at any time:**
```bash
bash scripts/10-demo-restore.sh
```

---

## Scenario 1: Orchestrator Unreachable

### The Story

A user submits a travel plan request. It never arrives. The entire AI system is dark — not because of a network failure, but because the entry point is down. ThousandEyes detects it before any user complaint.

### Setup

```bash
bash scripts/07-demo-orchestrator-down.sh
```

This scales the orchestrator deployment to 0 replicas. The Kubernetes service DNS entry still resolves, but there are no pods to accept connections — incoming requests receive a connection refused.

### What to Show

**ThousandEyes (~2 minutes after trigger):**

1. Open ThousandEyes → Test Settings → filter by your prefix
2. `[prefix] Agent - Orchestrator` → availability drops to **0%**, error: connection refused
3. All other 5 tests (flight, hotel, activity, synthesizer, LLM) remain **green**
4. Key point: TE detected the failure independently, before any user reported it, and pinpointed exactly which service is down

**Splunk APM (immediate):**

1. APM → Services → `orchestrator`
2. No new `travel.plan` traces appear — the service map goes dark
3. The load generator is still running and still sending requests, but nothing is getting through

**Splunk Alert:**

- Detector: `[Travel Planner] Scenario 1: Orchestrator Unreachable`
- Fires after **2 minutes** of zero requests
- Alert email includes:
  - Dynamic: severity, detector name, incident ID, timestamp
  - ThousandEyes orchestrator test link
  - Triage guidance (network vs. application)
  - SignalFlow for detection logic

### The Insight

> "ThousandEyes tells us the entry point to the AI system is down — independently, from inside the cluster, on the same network path your users would take. APM confirms no traffic is getting through. We know exactly what's broken before a single user calls the helpdesk."

### Restore

```bash
bash scripts/10-demo-restore.sh
```

---

## Scenario 2: Agent-to-Agent Communication Failure

### The Story

The orchestrator is healthy and accepting requests. Users can reach the system. But one specialist agent is unreachable — a partial failure that degrades output without a complete outage. ThousandEyes isolates exactly which agent-to-agent path failed.

### Setup

```bash
bash scripts/08-demo-agent-down.sh                    # defaults to flight-agent
AGENT=hotel-agent bash scripts/08-demo-agent-down.sh  # or any other agent
```

This scales the target agent to 0 replicas. The orchestrator will still complete `travel.plan` requests — it catches the connection error, substitutes fallback text ("Flight info unavailable"), and continues to the other agents.

### What to Show

**ThousandEyes (~2 minutes after trigger):**

1. Open ThousandEyes → Test Settings → filter by your prefix
2. `[prefix] Agent - Flight Specialist` → availability drops to **0%**, connection refused
3. `[prefix] Agent - Orchestrator`, Hotel, Activity, Synthesizer, and LLM tests → all **green**
4. Key point: the failure is precisely isolated to a single agent-to-agent network path

**Splunk APM (immediate on next /plan request):**

1. APM → Services → `orchestrator` → `travel.plan` operation
2. Click into a recent trace — notice the trace **completes** (orchestrator is still working)
3. Inside the trace: `agent.call.flight-agent` span → **ERROR** (connection refused)
4. Other agent spans (`hotel-agent`, `activity-agent`, `synthesizer`) → healthy, green
5. Click on the `agent.call.flight-agent` span → look at the Tags panel:
   - `te.test.id: 8724202`
   - `te.test.name: [prefix] Agent - Flight Specialist`
   - `te.test.url: https://app.thousandeyes.com/view/tests/?testId=8724202`
6. Click `te.test.id` → **"View in ThousandEyes"** button appears → opens directly to the failing test

**Splunk Alert:**

- Detector: `[Travel Planner] Scenario 2: Specialist Agent Unreachable`
- Fires after **2 minutes** of zero requests to the affected agent
- Alert email is specific to the agent — Flight Specialist alert links to the Flight Specialist TE test, not a generic link
- Other agents (hotel, activity, synthesizer) do not alert — they're healthy

### The Insight

> "One click from a failing APM span to the network evidence in ThousandEyes. The TE test that monitors the same path the orchestrator uses is right there on the span. We didn't have to search for it — it's embedded in the trace. And TE proves the other three agent paths are completely healthy, so we know exactly where to focus."

### Restore

```bash
bash scripts/10-demo-restore.sh
```

---

## Scenario 3: Agent-to-LLM Communication Failure

### The Story

All agents are running and responding to health checks. The orchestrator can reach every specialist. But every agent that calls the LLM is failing — requests time out after 10 seconds. Is this a network problem? ThousandEyes answers that immediately, before you even open the code.

### Setup

```bash
bash scripts/09-demo-llm-unreachable.sh
```

This reconfigures the LLM secret to point all agents at `http://192.0.2.1` — an RFC 5737 TEST-NET IP that is guaranteed non-routable. Agents connect, attempt to call the "LLM," time out after 10 seconds, and return a 500 error. The orchestrator receives a valid HTTP response (the agent responded with 500) but the itinerary content is degraded.

### What to Show

**ThousandEyes (immediate):**

1. Open ThousandEyes → Test Settings → filter by your prefix
2. All **5 agent health tests** → **green** (agents are up and responding to `/health`)
3. `[prefix] LLM - OpenAI Status` → **green** (`status.openai.com` is reachable from the cluster)
4. Key point: every ThousandEyes test is green — this is definitively **not a network problem**

**Splunk APM (~30 seconds after trigger):**

1. APM → Services → `flight-agent` → `POST /invoke` operation
2. Recent traces show **ERROR** status (HTTP 500)
3. Click into a trace — duration is ~31 seconds (OpenAI SDK retries 3× with 10s timeout each)
4. Inside `POST /invoke`, expand the span:
   - `exception.type: openai.APITimeoutError`
   - `exception.message: Request timed out.`
   - Full stacktrace: `httpx → ConnectTimeout → openai.APITimeoutError`
5. The same error appears in `hotel-agent`, `activity-agent`, and `synthesizer`
6. `orchestrator` → `travel.plan` trace **completes** with degraded output (agents return fallback text)

**Splunk Alert:**

- Detector: `[Travel Planner] Scenario 3: Agent LLM Calls Failing`
- Fires when 5xx errors from any specialist agent accumulate over a 2-minute window
- Alert email includes the LLM TE test link + triage guidance:
  - Network HEALTHY → check `base_url`, API key, or provider config
  - Network DEGRADED → investigate egress routing or firewall

### The Insight

> "ThousandEyes shows all network paths are healthy — the cluster can reach every agent, and the cluster can reach the LLM provider's network. So this is immediately off the network team's plate. APM shows the LLM call timing out inside each agent. The diagnosis is an application config issue: wrong base URL, invalid API key, or provider-side auth failure. TE gave us that answer before we opened a single log file."

### Restore

```bash
bash scripts/10-demo-restore.sh
```

---

## Alert Summary

All three detectors send email alerts to the configured recipients. Each alert includes:

| Field | Value |
|-------|-------|
| **Severity** | Critical (dynamic) |
| **Detector name** | Dynamic (`{{detectorName}}`) |
| **Incident ID** | Unique per incident (dynamic) |
| **Timestamp** | Time of detection (dynamic) |
| **ThousandEyes link** | Direct link to the specific test relevant to the failure |
| **Triage guidance** | Decision tree: network healthy vs. degraded |
| **APM guidance** | Exact service, operation, and span type to inspect |
| **Detection logic** | SignalFlow program that triggered the alert |

---

## Key Customer Talking Points

**1. Same network vantage as the application**
The ThousandEyes Enterprise Agent runs inside the same Kubernetes cluster as the travel planner. Its measurements are not from an external vantage — they reflect exactly what the orchestrator experiences when calling downstream agents.

**2. Bi-directional drilldowns require zero manual correlation**
The TE test ID is embedded in APM spans at trace time. There is no manual lookup, no copy-pasting test IDs, no switching between tools to find the right test. The link is on the span.

**3. Instant triage: network vs. application**
Scenario 3 is the most powerful demo for AI systems. All health checks pass, all agents respond. The failure is invisible to infrastructure monitoring. ThousandEyes' clean green status eliminates network as a cause in seconds — directing the team immediately to application-layer diagnosis.

**4. Partial failures are the hardest to detect**
Scenario 2 shows a degraded state where the system continues operating with reduced output. Traditional alerting on error rates might not fire immediately. ThousandEyes detects the network-layer failure independently, from inside the cluster, within 2 minutes.

**5. AI systems fail differently**
Agent-to-agent calls, LLM timeouts, partial degradation — these failure modes don't map cleanly to traditional service monitoring. This demo shows an observability pattern purpose-built for multi-agent AI architectures.

---

## Quick Reference

| Action | Command |
|--------|---------|
| Run Scenario 1 | `bash scripts/07-demo-orchestrator-down.sh` |
| Run Scenario 2 | `bash scripts/08-demo-agent-down.sh` |
| Run Scenario 2 (specific agent) | `AGENT=hotel-agent bash scripts/08-demo-agent-down.sh` |
| Run Scenario 3 | `bash scripts/09-demo-llm-unreachable.sh` |
| Restore everything | `bash scripts/10-demo-restore.sh` |
| Check pod status | `kubectl get deployments -n travel-planner` |
| Orchestrator logs | `kubectl logs -n travel-planner deployment/orchestrator -f` |
| Agent logs | `kubectl logs -n travel-planner deployment/flight-agent -f` |
| TE Agent logs | `kubectl logs -n te-demo -l app=thousandeyes -f` |

| Resource | URL |
|----------|-----|
| Splunk APM | `https://app.us1.signalfx.com` → APM → env: `petclinictesting-ecb9-workshop` |
| Splunk Dashboard | `https://app.us1.signalfx.com/#/dashboard/HKi7BHAA4AA` |
| ThousandEyes | `https://app.thousandeyes.com` → Test Settings → filter `petclinictesting-ecb9` |
