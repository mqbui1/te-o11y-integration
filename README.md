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
  - **Account Group Token** — for agent registration. Found at: Cloud & Enterprise Agents → Agent Settings → Add New Enterprise Agent
  - **User API Bearer Token** — for test creation via API. Found at: Account Settings → Users and Roles → User API Tokens

## Quick Start

```bash
git clone https://github.com/mqbui1/te-o11y-integration.git
cd te-o11y-integration

export TE_ACCOUNT_TOKEN="your-thousandeyes-account-group-token"
export TE_BEARER_TOKEN="your-thousandeyes-api-bearer-token"
export AGENT_HOSTNAME="your-name"   # becomes te-agent-your-name in TE dashboard
export TEST_PREFIX="your-name"      # prefix for all TE test names

chmod +x deploy.sh scripts/*.sh
./deploy.sh
```

The script auto-detects your agent ID once it's online and creates all tests. Total deployment time: ~3–5 minutes.

## What Gets Deployed

| Component | Namespace | Details |
|-----------|-----------|---------|
| Splunk OTel Collector | `default` | Helm chart v0.136.0, DaemonSet agent + cluster receiver + operator |
| PetClinic | `default` | 7 Java microservices + DB + load generator |
| Java auto-instrumentation | `default` | OTel operator injects agent into all PetClinic pods |
| ThousandEyes Enterprise Agent | `te-demo` | `thousandeyes/enterprise-agent:latest` |
| ThousandEyes Tests | — | 8 HTTP tests via API (4 in-cluster, 4 external) |

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
| `scripts/03-deploy-te-agent.sh` | Create `te-demo` namespace, apply credentials secret, deploy TE agent |
| `scripts/04-create-te-tests.sh` | Create all 8 ThousandEyes HTTP tests via API |
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

### ThousandEyes agent not appearing in dashboard
- Check pod status: `kubectl get pods -n te-demo`
- Check logs: `kubectl logs -n te-demo -l app=thousandeyes --tail=50`
- Agent registration can take 2–3 minutes after pod starts
- Verify the token is correct: `kubectl get secret te-creds -n te-demo -o yaml`

### PetClinic services not appearing in Splunk APM
- Confirm the Java instrumentation annotation was applied: `kubectl describe pod <api-gateway-pod> | grep inject`
- Check OTel Collector is exporting: `kubectl logs -l app=splunk-otel-collector --container otel-collector | grep -i export`
- Verify environment filter in Splunk matches `${INSTANCE}-workshop`

### ThousandEyes tests not streaming to Splunk
- Confirm a stream exists covering your tests: `curl -s https://api.thousandeyes.com/v7/stream -H "Authorization: Bearer ${TE_BEARER_TOKEN}"`
- Look for a stream with `"testMatch": []` (covers all tests) pointing to `ingest.{REALM}.signalfx.com`
- If no such stream exists, create one — see [How the Streaming Works](#how-the-thousandeyes--splunk-streaming-works) above

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
