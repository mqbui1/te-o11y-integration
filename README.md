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

Deployment order: Splunk OTel Collector → PetClinic → Travel Planner → ThousandEyes Agent → ThousandEyes Tests. Total time: ~8–12 minutes.

After deployment, two **one-time manual steps** are required for bi-directional drilldowns (see [Bi-directional Drilldowns Setup](#bi-directional-drilldowns-setup)):
- **Splunk**: Create a Global Data Link for `te.test.id`
- **ThousandEyes**: Create a Splunk APM Connector (requires Account Admin)

## What Gets Deployed

| Component | Namespace | Details |
|-----------|-----------|---------|
| Splunk OTel Collector | `default` | Helm chart, DaemonSet agent + cluster receiver + operator |
| Travel Planner | `travel-planner` | 5 Python Flask AI agents + CronJob load generator |
| PetClinic | `default` | 7 Java microservices (supplementary demo app) |
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

## Demo: Simulating an Agent Outage

Show how TE and APM together give faster root cause analysis than either alone.

### Run the outage

Scale down one of the specialist agents:

```bash
kubectl scale deployment flight-agent --replicas=0 -n travel-planner
```

### What to show in ThousandEyes

**app.thousandeyes.com → Test Settings** → filter `[your-prefix]`

- `[prefix] Agent - Flight Specialist` → availability drops to **0%**
- Error: connection refused / timeout from `te-agent-your-name`
- Exact timestamp of failure visible in the availability chart

> Tests run every 2 minutes — failure appears within the next cycle.

### What to show in Splunk APM

**APM → Environments: `${INSTANCE}-workshop`**

- `orchestrator` service map shows error rate on `agent.call.flight-agent` span
- Click the failing span → `te.test.id` tag → **"View in ThousandEyes"** button
- Span also shows `te.test.name` and `te.test.url` for direct navigation

### The narrative

> *"Your AI orchestrator is failing on flight searches. APM shows the `agent.call.flight-agent` span is erroring — and there's a ThousandEyes link right there on the span.*
>
> *Click it. TE has been running its own independent test of that exact agent from inside the cluster — the same network path your orchestrator uses. It confirms: connection refused. The flight-agent pod is down.*
>
> *No network issue. No LLM issue. One failed pod. You know in 30 seconds."*

### Restore

```bash
kubectl scale deployment flight-agent --replicas=1 -n travel-planner
```

ThousandEyes will show recovery within the next test cycle (~2 minutes).

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
| PetClinic app | `http://<EC2_PUBLIC_IP>:81` |

## Scripts

| Script | Description |
|--------|-------------|
| `deploy.sh` | Full end-to-end deployment |
| `scripts/01-install-otel-collector.sh` | Install Splunk OTel Collector via Helm |
| `scripts/02-deploy-travel-planner.sh` | Build + deploy all 5 travel planner agents |
| `scripts/02-deploy-petclinic.sh` | Deploy PetClinic + Java auto-instrumentation |
| `scripts/03-deploy-te-agent.sh` | Deploy ThousandEyes Enterprise Agent |
| `scripts/04-create-te-tests.sh` | Create TE tests, inject custom headers, update ConfigMap |
| `scripts/05-simulate-outage.sh` | Scale down PetClinic vets + visits services |
| `scripts/06-restore-services.sh` | Restore scaled-down PetClinic services |
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

## Supplementary: PetClinic

PetClinic (7 Java microservices) is included as a secondary demo showing Java auto-instrumentation via the OTel operator. It also has ThousandEyes tests for each service endpoint.

To simulate a PetClinic outage:

```bash
bash scripts/05-simulate-outage.sh   # scales down vets + visits services
bash scripts/06-restore-services.sh  # restores them
```

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
