# ThousandEyes + Splunk Observability Integration

Deploy a ThousandEyes Enterprise Agent inside a Kubernetes cluster alongside a PetClinic microservices app, with full Splunk Observability integration for APM traces, infrastructure metrics, and synthetic monitoring.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    k3d Kubernetes Cluster                    │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  PetClinic Microservices (default namespace)         │   │
│  │                                                      │   │
│  │  api-gateway ──→ customers-service                   │   │
│  │       └───────→ vets-service                         │   │
│  │       └───────→ visits-service                       │   │
│  │                                                      │   │
│  │  [Java OTel agent auto-injected by operator]         │   │
│  └──────────────┬───────────────────────────────────────┘   │
│                 │ traces + metrics                           │
│  ┌──────────────▼───────────────────────────────────────┐   │
│  │  Splunk OTel Collector (DaemonSet + Operator)        │   │
│  └──────────────┬───────────────────────────────────────┘   │
│                 │                                            │
│  ┌──────────────▼───────────────────────────────────────┐   │
│  │  ThousandEyes Enterprise Agent (te-demo namespace)   │   │
│  │                                                      │   │
│  │  HTTP tests → api-gateway.default.svc.cluster.local  │   │
│  │  HTTP tests → customers/vets/visits services         │   │
│  │  HTTP tests → external: Stripe, Splunk, TE platform  │   │
│  └──────────────┬───────────────────────────────────────┘   │
└─────────────────┼───────────────────────────────────────────┘
                  │
        ┌─────────┴──────────┐
        ▼                    ▼
Splunk OTel Collector    ThousandEyes Cloud
traces/metrics/logs      test results
        │                    │
        │              OTel metrics stream
        │              (HTTP → /v2/datapoint/otlp)
        └─────────┬──────────┘
                  ▼
     Splunk Observability Cloud
     ├── APM (traces, service map)
     ├── Infrastructure (K8s metrics)
     ├── Log Observer
     └── Synthetic dashboards (TE metrics)
```

The ThousandEyes agent runs **inside the same cluster** as PetClinic, giving it the same network vantage point as the application services themselves. This is the core value: when PetClinic's `api-gateway` calls `vets-service`, the TE agent can test that exact same path independently.

## How the ThousandEyes → Splunk Streaming Works

ThousandEyes streams test results to Splunk Observability Cloud via the **OpenTelemetry protocol** using a configured data stream:

1. In ThousandEyes UI: **Manage → Integrations 1.0 → New Integration → OpenTelemetry**
   - Target: `HTTP`
   - Endpoint URL: `https://ingest.{REALM}.signalfx.com/v2/datapoint/otlp`
   - Auth: Custom header `X-SF-Token: <ACCESS_TOKEN>`
   - Signal: `Metric`, Data Model: `v2`

2. Alternatively via the ThousandEyes API (required if UI creation is restricted):
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
   A stream with `"testMatch": []` (no filter) will stream **all tests** automatically — no need to update the stream when new tests are added.

3. Any ThousandEyes test assigned to your Enterprise Agent will have its results streamed as `thousandeyes.*` metrics in Splunk.

## ThousandEyes Token Guide

ThousandEyes uses **three distinct tokens** that are easy to confuse. Using the wrong one is the most common deployment failure.

| Token | What it's for | Where to find it | Format |
|-------|--------------|------------------|--------|
| **OAuth Bearer Token** (`TE_BEARER_TOKEN`) | API calls — creating tests, listing agents | Account Settings → Users and Roles → User API Tokens → **OAuth Bearer Token** tab | UUID: `1cd116ac-7ee2-...` |
| **Account Group Token** (`TE_ACCOUNT_TOKEN`) | Enterprise Agent registration with the TE platform | Cloud & Enterprise Agents → Agent Settings → **Add New Enterprise Agent** (Step 1 of wizard) | 32-char alphanumeric |
| **User API Token** (legacy) | Older Basic-auth API calls | Same page as OAuth Bearer, **User API Tokens** tab | 32-char alphanumeric — looks identical to Account Group Token but is not interchangeable |

> **Key point:** The Account Group Token and the User API Token are both 32-char alphanumeric strings and look identical. They are **not interchangeable**. If your agent registers but never comes online, you likely used the User API Token where the Account Group Token was needed.
>
> **Shortcut:** `scripts/03-deploy-te-agent.sh` can auto-fetch the Account Group Token from the API if you only have the OAuth Bearer Token — you don't need to find it manually.

## Prerequisites

- EC2 instance provisioned via [Splunk Show](https://show.splunk.com) with the following env vars pre-set in `/etc/environment`:

  | Variable | Description |
  |----------|-------------|
  | `ACCESS_TOKEN` | Splunk Observability ingest token |
  | `API_TOKEN` | Splunk Observability API token |
  | `REALM` | Splunk realm (e.g. `us1`) |
  | `INSTANCE` | Workshop instance name (e.g. `teo11y-2b93`) |
  | `CLUSTER_NAME` | k3d cluster name |
  | `HEC_URL` | Splunk HEC endpoint URL |
  | `HEC_TOKEN` | Splunk HEC token |
  | `RUM_FRONTEND_IP` | EC2 public IP |

- `kubectl`, `helm`, `curl`, `python3` available on the instance
- k3d Kubernetes cluster running (provisioned by cloud-init on workshop instances)
- A [ThousandEyes](https://app.thousandeyes.com) account with:
  - **OAuth Bearer Token** (`TE_BEARER_TOKEN`) — always required. Found at: Account Settings → Users and Roles → User API Tokens → OAuth Bearer Token tab
  - **Account Group Token** (`TE_ACCOUNT_TOKEN`) — for agent registration. Auto-fetched from the API if not provided. Found at: Cloud & Enterprise Agents → Agent Settings → Add New Enterprise Agent

## Quick Start

```bash
git clone https://github.com/mqbui1/te-o11y-integration.git
cd te-o11y-integration

# Only TE_BEARER_TOKEN is strictly required.
# TE_ACCOUNT_TOKEN is auto-fetched from the API if not set.
export TE_BEARER_TOKEN="your-oauth-bearer-token"   # UUID format
export TE_ACCOUNT_TOKEN=""                          # optional — auto-fetched if blank
export AGENT_HOSTNAME="your-name"                  # becomes te-agent-your-name in TE dashboard
export TEST_PREFIX="your-name"                     # prefix for all TE test names

# Travel planner LLM mode: "mock" (default, no API key), "openai", or "bedrock"
export LLM_PROVIDER=mock

chmod +x deploy.sh scripts/*.sh
./deploy.sh
```

The script deploys: Splunk OTel Collector → PetClinic → Travel Planner AI agents → ThousandEyes agent → ThousandEyes tests. Total deployment time: ~8–12 minutes (TE agent registration takes 2–3 min after pod start).

After deployment, complete these **one-time manual steps** in each tool (see [Distributed Tracing](#distributed-tracing-apm--thousandeyes-bi-directional-drilldowns) for details):
- **Splunk**: Create a Global Data Link for `te.test.id` → ThousandEyes URL
- **ThousandEyes**: Create a Splunk APM Connector (requires Account Admin)

## What Gets Deployed

| Component | Namespace | Details |
|-----------|-----------|---------|
| Splunk OTel Collector | `default` | Helm chart v0.136.0, DaemonSet agent + cluster receiver + operator |
| PetClinic | `default` | 7 Java microservices + DB + load generator |
| Java auto-instrumentation | `default` | OTel operator injects agent into all PetClinic pods |
| Travel Planner agents | `travel-planner` | 5 Python Flask microservices + CronJob load generator |
| ThousandEyes Enterprise Agent | `te-demo` | `thousandeyes/enterprise-agent:latest` |
| ThousandEyes Tests | — | 9 HTTP tests (5 agent health, 1 LLM endpoint, 3 external) |

## Travel Planner — Multi-Agent AI Observability

The travel planner demonstrates ThousandEyes + Splunk APM on an AI multi-agent system. Each agent is a separate HTTP microservice so ThousandEyes can monitor **agent-to-agent** and **agent-to-LLM** connectivity independently.

```
travel-planner namespace
├── orchestrator     POST /plan   — routes requests, calls all agents via HTTP
├── flight-agent     POST /invoke — flight search specialist
├── hotel-agent      POST /invoke — hotel recommendation specialist
├── activity-agent   POST /invoke — activities curation specialist
└── synthesizer      POST /invoke — combines results into final itinerary

ThousandEyes tests (from te-demo namespace, same network vantage as agents):
├── Agent - Orchestrator /health
├── Agent - Flight Specialist /health
├── Agent - Hotel Specialist /health
├── Agent - Activity Specialist /health
├── Agent - Synthesizer /health
└── LLM - OpenAI API (or Bedrock endpoint)

OTel trace context propagated via W3C headers → full distributed trace in Splunk APM
```

### Design Notes

- **No k8s liveness/readiness probes** — intentionally removed from all 5 travel-planner deployments. Probes generate constant `kube-probe/1.33` spans in Splunk APM that bury the ThousandEyes-originated `/health` spans. ThousandEyes tests every 2 minutes serve the same availability monitoring purpose for this demo.

### Deploying the Travel Planner

```bash
# Mock mode — no LLM required, exercises all HTTP paths (good for TE monitoring demo)
LLM_PROVIDER=mock bash scripts/02-deploy-travel-planner.sh

# With OpenAI
OPENAI_API_KEY=sk-... LLM_PROVIDER=openai bash scripts/02-deploy-travel-planner.sh

# With AWS Bedrock (uses IAM role on EC2, no key needed)
LLM_PROVIDER=bedrock AWS_DEFAULT_REGION=us-east-1 bash scripts/02-deploy-travel-planner.sh
```

### Travel Planner ThousandEyes Tests

| Test Name | Target | What it monitors |
|-----------|--------|-----------------|
| `[prefix] Agent - Orchestrator` | `/health` in-cluster | Entry point availability |
| `[prefix] Agent - Flight Specialist` | `/health` in-cluster | Agent-to-agent path |
| `[prefix] Agent - Hotel Specialist` | `/health` in-cluster | Agent-to-agent path |
| `[prefix] Agent - Activity Specialist` | `/health` in-cluster | Agent-to-agent path |
| `[prefix] Agent - Synthesizer` | `/health` in-cluster | Agent-to-agent path |
| `[prefix] LLM - OpenAI API` | `api.openai.com` | Agent-to-LLM connectivity |

The TE agent runs inside the same cluster as the travel planner, so its latency measurements reflect **exactly what the agents experience** — not what the network looks like from outside. When APM shows slow LLM response times, TE tells you whether the slowness is network-level or application-level.

### Distributed Tracing: APM ↔ ThousandEyes Bi-directional Drilldowns

The travel planner is configured for full bi-directional correlation between Splunk APM spans and ThousandEyes test results.

#### TE → APM (ThousandEyes initiates the trace)

1. All 5 agent `/health` tests have `distributedTracing: true` — TE injects B3 headers into every request
2. `04-create-te-tests.sh` also configures `X-TE-Test-Id` and `X-TE-Test-Name` custom headers on each test
3. Each service has a `B3Format` propagator and `ParentBased(ALWAYS_ON)` sampler (`shared/otel_setup.py`)
4. Each `/health` view function calls `stamp_te_span()` which copies those custom headers onto the active OTel span as `te.test.id`, `te.test.name`, and `te.test.url`

Result: TE-originated health checks appear in Splunk APM as full distributed traces with ThousandEyes metadata embedded in the span.

#### APM → TE (Splunk APM links back to ThousandEyes)

The orchestrator stamps every `agent.call.*` span with `te.test.id`, `te.test.name`, and `te.test.url` from the `te-test-ids` ConfigMap (populated by `04-create-te-tests.sh`). A Splunk Global Data Link renders `te.test.id` as a clickable **"View in ThousandEyes"** button in the span detail panel.

**Splunk Global Data Links setup (one-time):**

In Splunk Observability Cloud → **Settings → Global Data Links → New Link**:

| Field | Value |
|-------|-------|
| Link label | `View in ThousandEyes` |
| Show on | Metric or property name |
| Metric/property name | `te.test.id` |
| URL | `https://app.thousandeyes.com/view/tests/?testId={{value}}` |

#### ThousandEyes APM Connector (one-time, requires Account Admin)

Enables a **"View in APM"** link on ThousandEyes test result pages. In ThousandEyes UI:

**Manage → Integrations → Integrations 2.0 → Connectors → New Connector**

- Type: Generic Connector, Preset: **Splunk Observability APM**
- Target URL: `https://api.<REALM>.signalfx.com`
- Header: `X-SF-Token: <api-scope-access-token>`

> Requires Account Admin in ThousandEyes. Cannot be created via the API (returns 405).

### PetClinic Services

| Service | Port | Role |
|---------|------|------|
| `api-gateway` | 8080 | Entry point, routes to all services |
| `customers-service` | 8080 | Owner and pet management |
| `vets-service` | 8080 | Veterinarian data |
| `visits-service` | 8080 | Appointment visits |
| `config-server` | 8888 | Centralized config |
| `discovery-server` | 8761 | Eureka service registry |
| `petclinic-db` | 3306 | MySQL database |
| `petclinic-loadgen` | — | Continuous traffic generator |

### ThousandEyes Tests Created

| Test Name | Type | Target |
|-----------|------|--------|
| `[prefix] PetClinic Frontend` | HTTP | `api-gateway.default.svc.cluster.local:8080` |
| `[prefix] PetClinic Owners API` | HTTP | `customers-service.default.svc.cluster.local:8080/owners` |
| `[prefix] PetClinic Vets API` | HTTP | `vets-service.default.svc.cluster.local:8080/vets` |
| `[prefix] PetClinic Visits API` | HTTP | `visits-service.default.svc.cluster.local:8080/visits` |
| `[prefix] EC2 Instance Health` | HTTP | `http://<EC2_PUBLIC_IP>` |
| `[prefix] Stripe API Health` | HTTP | `https://api.stripe.com/healthcheck` |
| `[prefix] Splunk Observability Cloud` | HTTP | `https://app.us1.signalfx.com` |
| `[prefix] ThousandEyes Platform` | HTTP | `https://app.thousandeyes.com` |

## Scripts

| Script | Description |
|--------|-------------|
| `deploy.sh` | Full end-to-end deployment (runs all steps) |
| `scripts/01-install-otel-collector.sh` | Add Helm repo, create `workshop-secret`, install Splunk OTel Collector |
| `scripts/02-deploy-petclinic.sh` | Deploy PetClinic manifests + patch Java auto-instrumentation on all services |
| `scripts/02-deploy-travel-planner.sh` | Build travel-planner image, import into k3d, deploy all 5 agent services |
| `scripts/03-deploy-te-agent.sh` | Create `te-demo` namespace, deploy TE agent (auto-fetches Account Group Token) |
| `scripts/04-create-te-tests.sh` | Create ThousandEyes HTTP tests for PetClinic + travel planner agents |
| `scripts/05-simulate-outage.sh` | Scale down `vets-service` + `visits-service` to simulate outage |
| `scripts/06-restore-services.sh` | Restore scaled-down services to replicas=1 |
| `teardown.sh` | Remove PetClinic, TE agent, and OTel Collector |

## Demo: Simulating a Service Outage

This is the key demo scenario — showing how ThousandEyes and Splunk APM together give faster, more complete root cause analysis than either tool alone.

### Run the outage

```bash
# Simulate outage (scales down vets-service + visits-service)
bash scripts/05-simulate-outage.sh

# Or auto-restore after 5 minutes
DURATION=300 bash scripts/05-simulate-outage.sh
```

### What to show in ThousandEyes

Navigate to: **app.thousandeyes.com → Cloud & Enterprise Agents → Test Settings** → filter by `[your-prefix]`

- `[prefix] PetClinic Vets API` → availability drops to **0%**
- `[prefix] PetClinic Visits API` → availability drops to **0%**
- Error detail: `Connection timed out after ~5000ms` from `te-agent-your-name`
- The availability chart shows the exact timestamp the services went down

> Tests run every 2 minutes — you'll see the failure reflected within the next test cycle.

### What to show in Splunk APM

Navigate to: **app.us1.signalfx.com → APM → Environments: `${INSTANCE}-workshop`**

- `vets-service` and `visits-service` disappear from the service map
- `api-gateway` shows error rate spike (upstream calls failing)
- Trace detail shows `ConnectionRefused` / timeout errors on downstream calls

### The narrative

> *"ThousandEyes answers the question APM can't: is this a network problem or an application problem?*
>
> *The TE agent runs inside the cluster — it has the exact same network path as our services. When it reports a connection timeout to `vets-service`, we know the issue is the service itself, not the network between the gateway and the service. APM confirms it: the service is dark, not degraded.*
>
> *Together, they cut mean-time-to-innocence in half: network team sees TE data and immediately knows it's not their problem. App team sees APM and pinpoints the failed pod. No war room needed."*

### Restore

```bash
bash scripts/06-restore-services.sh
```

ThousandEyes tests will show recovery (back to 100% availability) within the next test cycle (~2 minutes).

## Accessing the Environment

| Resource | URL / Command |
|----------|---------------|
| PetClinic app | `http://<EC2_PUBLIC_IP>:81` |
| PetClinic (alt ports) | `:80` or `:443` |
| Splunk APM | `https://app.us1.signalfx.com` → APM → filter env: `${INSTANCE}-workshop` |
| Splunk Infra | `https://app.us1.signalfx.com` → Infrastructure → K8s navigator |
| ThousandEyes | `https://app.thousandeyes.com` → Test Settings → filter `[your-prefix]` |
| OTel Collector logs | `kubectl logs -l app=splunk-otel-collector -f --container otel-collector` |
| TE Agent logs | `kubectl logs -n te-demo -l app=thousandeyes -f` |

## Troubleshooting

### ThousandEyes agent pod running but never appears in dashboard

**Most common cause: wrong token used for `TEAGENT_ACCOUNT_TOKEN`.**

The User API Token (32-char alphanumeric) and the Account Group Token look identical but are not interchangeable. The agent will start and the browserbot will initialize successfully, but the agent will silently fail to register if the wrong token is used — there is no error in the pod logs.

Fix: let the script auto-fetch the correct token, or get it manually:
```bash
# Auto-fetch via API (easiest)
unset TE_ACCOUNT_TOKEN
export TE_BEARER_TOKEN="your-oauth-bearer-token"
bash scripts/03-deploy-te-agent.sh

# Or fetch manually and inspect
curl -s https://api.thousandeyes.com/v7/account-groups \
  -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
  | python3 -c "
import json, sys
for ag in json.load(sys.stdin).get('accountGroups', []):
    print(ag['aid'], ag['accountGroupName'])
    print('  token:', ag.get('accountToken', 'NOT RETURNED - get from UI'))
"
```

Other checks:
- Pod status: `kubectl get pods -n te-demo`
- Pod logs: `kubectl logs -n te-demo -l app=thousandeyes --tail=50`
- Agent registration takes 2–3 minutes after browserbot finishes initializing
- Verify stored token: `kubectl get secret te-creds -n te-demo -o jsonpath="{.data.TEAGENT_ACCOUNT_TOKEN}" | base64 -d | wc -c` (should be 32 chars)

### Travel planner pods in CrashLoopBackOff
- Check logs: `kubectl logs -n travel-planner deployment/flight-agent`
- Verify image was imported: `docker exec k3d-<cluster>-server-0 crictl images | grep travel-planner`
- Re-import if missing: `k3d image import travel-planner:latest -c ${CLUSTER_NAME}`
- If LLM calls are failing, switch to mock mode: update `llm-secret` with `mock_mode=true`

```bash
kubectl create secret generic llm-secret --namespace travel-planner \
  --from-literal=provider="mock" --from-literal=mock_mode="true" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment -n travel-planner
```

### PetClinic services not appearing in Splunk APM
- Confirm the Java instrumentation annotation was applied: `kubectl describe pod <api-gateway-pod> | grep inject`
- Check OTel Collector is exporting: `kubectl logs -l app=splunk-otel-collector --container otel-collector | grep -i export`
- Verify environment filter in Splunk matches `${INSTANCE}-workshop`

### ThousandEyes tests not streaming to Splunk
- Confirm a stream exists covering your tests: `curl -s https://api.thousandeyes.com/v7/stream -H "Authorization: Bearer ${TE_BEARER_TOKEN}"`
- Look for a stream with `"testMatch": []` (covers all tests) pointing to `ingest.{REALM}.signalfx.com`
- If no such stream exists, create one — see [How the Streaming Works](#how-the-thousandeyes--splunk-streaming-works) above

### `te.*` span attributes missing on `/health` spans

- The `/health` view function must call `stamp_te_span()` directly — a Flask `after_request` hook does not reliably stamp attributes before the span closes.
- Verify the TE test has `X-TE-Test-Id` and `X-TE-Test-Name` custom headers and `distributedTracing: true`. Re-run `04-create-te-tests.sh` if tests were created before this was in place:
  ```bash
  bash scripts/04-create-te-tests.sh
  ```
- **Important:** A partial PUT to the TE API silently resets `distributedTracing` to `false`. The script uses a full GET→merge→PUT cycle to preserve all fields. Verify both are set:
  ```bash
  curl -s https://api.thousandeyes.com/v7/tests/http-server/<TEST_ID> \
    -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
    | python3 -c "import json,sys; t=json.load(sys.stdin); print('distributedTracing:', t.get('distributedTracing')); print('customHeaders:', t.get('customHeaders'))"
  ```
- After redeployment, the `te-test-ids` ConfigMap and orchestrator restart are handled automatically by `04-create-te-tests.sh`.

### `/health` spans flooded with `kube-probe/1.33` requests hiding TE spans

K8s liveness/readiness probes are intentionally **disabled** on all travel-planner deployments. If you re-enable them or deploy from scratch with probes, TE-originated spans will be buried by probe traffic. The manifests in `manifests/travel-planner/` have no `livenessProbe` or `readinessProbe` sections by design.

### "View in ThousandEyes" button not appearing in APM span detail

The Global Data Link must be configured in Splunk (one-time). See [Distributed Tracing: APM ↔ ThousandEyes](#distributed-tracing-apm--thousandeyes-bi-directional-drilldowns) above. The button appears when clicking the `te.test.id` property in the span detail panel — not as a floating link.

### `workshop-secret` already exists error
The secret is pre-created on some workshop instances. The scripts use `--dry-run=client | kubectl apply` to handle this idempotently.

## Finding Your ThousandEyes Agent ID

After running step 3, the agent ID is auto-detected by `deploy.sh`. To look it up manually:

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

## Teardown

```bash
./teardown.sh
```

Removes PetClinic deployments, the `te-demo` namespace (TE agent), and uninstalls the Splunk OTel Collector Helm release. ThousandEyes tests and streams must be deleted manually from the ThousandEyes UI/API.
