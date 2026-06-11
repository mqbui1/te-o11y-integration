# ThousandEyes + Splunk Observability: AI Agent Monitoring

Monitor an AI multi-agent travel planner with ThousandEyes synthetic tests and Splunk APM — with bi-directional drilldowns between network-layer visibility and distributed traces.

## The Problem This Solves

When an AI orchestrator calls a downstream agent and latency spikes, you get one question: **is this a network problem or an application problem?**

ThousandEyes runs inside the same Kubernetes cluster as your agents — giving it the exact same network path. When APM shows a slow `flight-agent` call, TE tells you immediately whether the network between the orchestrator and that agent is healthy. No war room. No finger-pointing.

## Architecture

```
                     User / Load Generator
                             │
                             ▼ POST /plan
┌────────────────────────────────────────────────────────────┐
│                   travel-planner namespace                  │
│                                                            │
│   orchestrator ──→ flight-agent    ← TE health test        │
│        │       ──→ hotel-agent     ← TE health test        │
│        │       ──→ activity-agent  ← TE health test        │
│        │       ──→ synthesizer     ← TE health test        │
│        │                                                    │
│        └──→ [LLM: OpenAI / Bedrock]  ← TE LLM test        │
│                                                            │
│   te-demo namespace                                        │
│   └── ThousandEyes Enterprise Agent                        │
│         (same network vantage as agents)                   │
│                                                            │
│   Splunk OTel Collector (DaemonSet)                        │
│   └── receives traces + metrics from all services          │
└────────────────────────────────────────────────────────────┘
          │                          │
          ▼                          ▼
  Splunk Observability Cloud    ThousandEyes Cloud
  ├── APM: distributed traces   ├── HTTP test results
  ├── Service map                ├── Network path vis
  └── Infrastructure metrics    └── Availability metrics
          │                          │
          └──────────┬───────────────┘
                     ▼
           Bi-directional drilldowns:
           APM span → "View in ThousandEyes"
           TE test  → "View in APM"
```

## How the Demo Works

The travel planner is a 5-service AI system:

```
orchestrator  POST /plan
  ├── flight-agent    POST /invoke  — flight search specialist
  ├── hotel-agent     POST /invoke  — hotel recommendation specialist
  ├── activity-agent  POST /invoke  — activities curation specialist
  └── synthesizer     POST /invoke  — combines results into itinerary
```

ThousandEyes tests each agent's `/health` endpoint from inside the cluster every 2 minutes. Because the TE agent is co-located, its measurements reflect exactly what `orchestrator` experiences when it calls each downstream agent.

**When something is slow or failing:**
- APM shows which `agent.call.*` span is slow — with a "View in ThousandEyes" link on the span
- TE shows whether the network path to that agent is degraded — with a "View in APM" link from the test result
- Together: network root cause vs application root cause in seconds, not hours

## Quick Start

```bash
git clone https://github.com/mqbui1/te-o11y-integration.git
cd te-o11y-integration

# TE_BEARER_TOKEN is required (UUID format OAuth Bearer Token).
# TE_ACCOUNT_TOKEN is auto-fetched if not set.
export TE_BEARER_TOKEN="your-oauth-bearer-token"
export AGENT_HOSTNAME="your-name"   # becomes te-agent-your-name in TE dashboard
export TEST_PREFIX="your-name"      # prefix for all TE test names

# LLM mode: "mock" (default, no key needed), "openai", or "bedrock"
export LLM_PROVIDER=mock

chmod +x deploy.sh scripts/*.sh
./deploy.sh
```

Deployment order: Splunk OTel Collector → Travel Planner → ThousandEyes Agent → ThousandEyes Tests. Total time: ~8–12 minutes.

After deployment, two **one-time manual steps** are required for bi-directional drilldowns (see [Bi-directional Drilldowns Setup](#bi-directional-drilldowns-setup)):
- **Splunk**: Create a Global Data Link for `te.test.id`
- **ThousandEyes**: Create a Splunk APM Connector (requires Account Admin)

## What Gets Deployed

| Component | Namespace | Details |
|-----------|-----------|---------|
| Splunk OTel Collector | `default` | Helm chart, DaemonSet agent + cluster receiver + operator |
| Travel Planner | `travel-planner` | 5 Python Flask AI agents + CronJob load generator |
| ThousandEyes Enterprise Agent | `te-demo` | Co-located in cluster for accurate network measurements |
| ThousandEyes Tests | — | 5 agent health tests + 1 LLM + 4 external |

## ThousandEyes Tests

| Test | Target | Purpose |
|------|--------|---------|
| `[prefix] Agent - Orchestrator` | `/health` in-cluster | Entry point availability |
| `[prefix] Agent - Flight Specialist` | `/health` in-cluster | Orchestrator→agent network path |
| `[prefix] Agent - Hotel Specialist` | `/health` in-cluster | Orchestrator→agent network path |
| `[prefix] Agent - Activity Specialist` | `/health` in-cluster | Orchestrator→agent network path |
| `[prefix] Agent - Synthesizer` | `/health` in-cluster | Orchestrator→agent network path |
| `[prefix] LLM - OpenAI API` | `api.openai.com` | Agent→LLM connectivity |
| `[prefix] EC2 Instance Health` | `http://<EC2_IP>` | External reachability |
| `[prefix] Splunk Observability Cloud` | `app.us1.signalfx.com` | Splunk platform reachability |
| `[prefix] ThousandEyes Platform` | `app.thousandeyes.com` | TE platform reachability |

All 5 agent health tests run with `distributedTracing: true` — TE injects B3 trace headers so each test appears as a root span in Splunk APM.

## Bi-directional Drilldowns Setup

### How it works end-to-end

**TE → APM** (ThousandEyes health check appears in Splunk APM):
1. TE test sends request with B3 headers + custom headers `X-TE-Test-Id` and `X-TE-Test-Name`
2. Service extracts B3 context (B3 propagator, `ParentBased(ALWAYS_ON)` sampler in `shared/otel_setup.py`)
3. `/health` view function calls `stamp_te_span()` → sets `te.test.id`, `te.test.name`, `te.test.url` on the span
4. Span appears in Splunk APM tagged with which TE test triggered it

**APM → TE** (Splunk APM span links to ThousandEyes test):
1. Orchestrator reads test IDs from `te-test-ids` ConfigMap (populated by `04-create-te-tests.sh`)
2. Every `agent.call.*` span is tagged with `te.test.id`, `te.test.name`, `te.test.url`
3. Splunk Global Data Link renders `te.test.id` as a "View in ThousandEyes" button

### Splunk Global Data Links (one-time)

**Settings → Global Data Links → New Link**:

| Field | Value |
|-------|-------|
| Link label | `View in ThousandEyes` |
| Show on | Metric or property name |
| Property name | `te.test.id` |
| URL | `https://app.thousandeyes.com/view/tests/?testId={{value}}` |

### ThousandEyes APM Connector (one-time, requires Account Admin)

Enables "View in APM" from ThousandEyes test results.

**Manage → Integrations → Integrations 2.0 → Connectors → New Connector**:
- Preset: **Splunk Observability APM**
- Target URL: `https://api.<REALM>.signalfx.com`
- Header: `X-SF-Token: <api-scope-access-token>`

> Cannot be created via API (returns 405). Requires Account Admin role in ThousandEyes.

## Demo Scenarios

Three scenarios showing how ThousandEyes and Splunk APM together give instant root cause clarity on AI agent failures. Run any scenario, walk through both tools, then restore.

```bash
bash scripts/10-demo-restore.sh   # always safe to run — resets everything
```

---

### Scenario 1: Orchestrator Unreachable

**Story:** A user submits a travel plan request. It never arrives. The entry point to the entire AI system is down.

```bash
bash scripts/07-demo-orchestrator-down.sh
```

| Tool | What you see |
|------|-------------|
| **ThousandEyes** | `[prefix] Agent - Orchestrator` → availability 0%, connection refused. All other tests green. |
| **Splunk APM** | No new `travel.plan` traces appear. Orchestrator goes dark on the service map. |

**The insight:** TE detects the entry point is down independently — before any user complaint. APM confirms no traffic is getting through.

---

### Scenario 2: Agent-to-Agent Communication Failure

**Story:** The orchestrator is healthy and accepting requests, but one specialist agent is unreachable. The AI system partially degrades.

```bash
bash scripts/08-demo-agent-down.sh                    # defaults to flight-agent
AGENT=hotel-agent bash scripts/08-demo-agent-down.sh  # or any other agent
```

| Tool | What you see |
|------|-------------|
| **ThousandEyes** | `[prefix] Agent - Flight Specialist` → 0% availability. All other agent tests remain green. Proves the failure is isolated to that one path. |
| **Splunk APM** | `travel.plan` trace completes. `agent.call.flight-agent` span → ERROR. Click `te.test.id` on that span → **"View in ThousandEyes"** button. Other agent spans healthy. |

**The insight:** TE isolates exactly which agent-to-agent path failed. APM links directly to the TE test — one click from a failing span to network-layer evidence.

---

### Scenario 3: Agent-to-LLM Communication Failure

**Story:** All agents are reachable and responding to health checks. But every agent that tries to call the LLM is failing. Is it a network problem?

```bash
bash scripts/09-demo-llm-unreachable.sh
```

| Tool | What you see |
|------|-------------|
| **ThousandEyes** | `[prefix] LLM - OpenAI API` → **still green**. All 5 agent health tests → still green. |
| **Splunk APM** | `agent.call.*` spans all succeed. LangChain spans inside each agent → ERROR (connection timeout to LLM). `travel.plan` returns degraded output. |

**The insight:** TE shows the network path to the LLM is healthy — this is NOT a network problem. The failure is application-layer: bad configuration, wrong URL, or auth issue. TE gives you instant triage before you even open the code.

---

### Restore

```bash
bash scripts/10-demo-restore.sh
```

Restores all agents to 1 replica and resets LLM config to mock mode. ThousandEyes tests return to green within ~2 minutes.

## Deploying the Travel Planner Standalone

```bash
# Mock mode — no LLM required, all HTTP paths exercised
LLM_PROVIDER=mock bash scripts/02-deploy-travel-planner.sh

# With OpenAI
OPENAI_API_KEY=sk-... LLM_PROVIDER=openai bash scripts/02-deploy-travel-planner.sh

# With AWS Bedrock (IAM role on EC2, no key needed)
LLM_PROVIDER=bedrock AWS_DEFAULT_REGION=us-east-1 bash scripts/02-deploy-travel-planner.sh
```

Test it manually:

```bash
kubectl run -it --rm test --image=curlimages/curl --restart=Never -n travel-planner -- \
  curl -X POST http://orchestrator.travel-planner.svc.cluster.local:8080/plan \
    -H 'Content-Type: application/json' \
    -d '{"origin": "Seattle", "destination": "Paris", "travellers": 2}'
```

## Accessing the Environment

| Resource | URL / Command |
|----------|---------------|
| Splunk APM | `https://app.us1.signalfx.com` → APM → env: `${INSTANCE}-workshop` |
| ThousandEyes | `https://app.thousandeyes.com` → Test Settings → filter `[your-prefix]` |
| Travel planner logs | `kubectl logs -n travel-planner deployment/orchestrator -f` |
| OTel Collector logs | `kubectl logs -l app=splunk-otel-collector -f --container otel-collector` |
| TE Agent logs | `kubectl logs -n te-demo -l app=thousandeyes -f` |

## Scripts

| Script | Description |
|--------|-------------|
| `deploy.sh` | Full end-to-end deployment |
| `scripts/01-install-otel-collector.sh` | Install Splunk OTel Collector via Helm |
| `scripts/02-deploy-travel-planner.sh` | Build + deploy all 5 travel planner agents |
| `scripts/03-deploy-te-agent.sh` | Deploy ThousandEyes Enterprise Agent |
| `scripts/04-create-te-tests.sh` | Create TE tests, inject custom headers, update ConfigMap |
| `scripts/07-demo-orchestrator-down.sh` | Demo 1: scale orchestrator to 0 (entry point unreachable) |
| `scripts/08-demo-agent-down.sh` | Demo 2: scale one agent to 0 (`AGENT=flight-agent` default) |
| `scripts/09-demo-llm-unreachable.sh` | Demo 3: switch to openai mode with unreachable LLM URL |
| `scripts/10-demo-restore.sh` | Restore all travel planner services to normal |
| `teardown.sh` | Remove all deployments |

## ThousandEyes Token Guide

| Token | Purpose | Where to find it | Format |
|-------|---------|-----------------|--------|
| **OAuth Bearer Token** (`TE_BEARER_TOKEN`) | API calls — creating tests, agents | Account Settings → User API Tokens → **OAuth Bearer Token** tab | UUID |
| **Account Group Token** (`TE_ACCOUNT_TOKEN`) | Enterprise Agent registration | Cloud & Enterprise Agents → Agent Settings → Add New Agent | 32-char alphanumeric |

> The Account Group Token and User API Token are both 32-char alphanumeric and look identical — they are **not interchangeable**. `scripts/03-deploy-te-agent.sh` auto-fetches the correct Account Group Token if you only have the Bearer Token.

## Troubleshooting

### `te.*` span attributes missing on `/health` spans

- Verify the TE test has `distributedTracing: true` and `X-TE-Test-Id`/`X-TE-Test-Name` custom headers. Re-run `04-create-te-tests.sh` to fix:
  ```bash
  bash scripts/04-create-te-tests.sh
  ```
- **Partial PUT to TE API silently resets `distributedTracing` to `false`** — the script uses GET→merge→PUT to prevent this. Verify:
  ```bash
  curl -s https://api.thousandeyes.com/v7/tests/http-server/<TEST_ID> \
    -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
    | python3 -c "import json,sys; t=json.load(sys.stdin); print('distributedTracing:', t.get('distributedTracing')); print('customHeaders:', t.get('customHeaders'))"
  ```
- `stamp_te_span()` must be called directly in the view function — a Flask `after_request` hook does not work reliably.

### `/health` spans flooded with `kube-probe/1.33` traffic

K8s liveness/readiness probes are **intentionally disabled** on all travel-planner services. They generate constant noise in APM that buries TE-originated spans. The manifests in `manifests/travel-planner/` have no probe sections — do not add them. TE tests every 2 minutes serve the same availability monitoring role.

### "View in ThousandEyes" button not appearing

The Splunk Global Data Link must be configured (one-time). The button appears when clicking the `te.test.id` tag in the span detail panel. See [Bi-directional Drilldowns Setup](#bi-directional-drilldowns-setup).

### Travel planner pods in CrashLoopBackOff

```bash
kubectl logs -n travel-planner deployment/flight-agent
# If image missing after cluster restart:
k3d image import travel-planner:latest -c ${CLUSTER_NAME}
# Switch to mock mode if LLM calls are failing:
kubectl create secret generic llm-secret --namespace travel-planner \
  --from-literal=provider="mock" --from-literal=mock_mode="true" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment -n travel-planner
```

### ThousandEyes agent never appears in dashboard

Wrong token used for `TEAGENT_ACCOUNT_TOKEN` — the User API Token and Account Group Token look identical but are not interchangeable. Let the script auto-fetch it:

```bash
unset TE_ACCOUNT_TOKEN
bash scripts/03-deploy-te-agent.sh
```

Check: `kubectl logs -n te-demo -l app=thousandeyes --tail=50`

### ThousandEyes tests not streaming to Splunk

```bash
curl -s https://api.thousandeyes.com/v7/stream \
  -H "Authorization: Bearer ${TE_BEARER_TOKEN}"
```

Look for a stream with `"testMatch": []` pointing to `ingest.{REALM}.signalfx.com`. If missing, create one — see [How the ThousandEyes → Splunk Streaming Works](#how-the-thousandeyes--splunk-streaming-works).

## How the ThousandEyes → Splunk Streaming Works

ThousandEyes streams test results to Splunk via the OpenTelemetry protocol:

```bash
curl -XPOST https://api.thousandeyes.com/v7/stream \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
  -d '{
    "type": "opentelemetry",
    "endpointType": "http",
    "streamEndpointUrl": "https://ingest.us1.signalfx.com/v2/datapoint/otlp",
    "customHeaders": {
      "X-SF-Token": "<ACCESS_TOKEN>",
      "Content-Type": "application/x-protobuf"
    }
  }'
```

A stream with `"testMatch": []` covers all tests automatically — no updates needed when new tests are added.

## Teardown

```bash
./teardown.sh
```

## Finding Your ThousandEyes Agent ID

```bash
curl -s https://api.thousandeyes.com/v7/agents \
  -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
  | python3 -c "
import json, sys
for a in json.load(sys.stdin)['agents']:
    if 'your-name' in a['agentName']:
        print(a['agentId'], a['agentName'], a['agentState'])
"
```
