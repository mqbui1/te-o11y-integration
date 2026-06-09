# ThousandEyes + Splunk Observability Integration

Deploy a ThousandEyes Enterprise Agent inside a Kubernetes cluster alongside a PetClinic microservices app, with full Splunk Observability integration for APM traces, infrastructure metrics, and synthetic monitoring.

## Architecture

```
PetClinic (k3d / Kubernetes)
        ↓  Java OTel auto-instrumentation
Splunk OTel Collector
        ↓  traces + metrics + logs
Splunk Observability Cloud (APM, Infrastructure, Log Observer)

ThousandEyes Enterprise Agent (in-cluster)
        ↓  HTTP tests (internal + external)
ThousandEyes Cloud
        ↓  OTel metrics stream
Splunk Observability Cloud (Synthetics / dashboards)
```

The ThousandEyes agent runs **inside the same cluster** as PetClinic, giving it the same network vantage point as the application services themselves.

## Prerequisites

- EC2 instance provisioned via [Splunk Show](https://show.splunk.com) with the following env vars pre-set in `/etc/environment`:
  - `ACCESS_TOKEN`, `REALM`, `INSTANCE`, `HEC_URL`, `HEC_TOKEN`, `RUM_FRONTEND_IP`
- `kubectl`, `helm`, `curl` available on the instance
- k3d Kubernetes cluster running (provisioned by cloud-init)
- A [ThousandEyes](https://app.thousandeyes.com) account with:
  - **Account Group Token** (for agent registration)
  - **User API Bearer Token** (for test creation via API)

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

## What Gets Deployed

| Component | Details |
|-----------|---------|
| Splunk OTel Collector | Helm chart v0.136.0, operator mode, Java auto-instrumentation enabled |
| PetClinic | 7 Java microservices + DB + load generator, all auto-instrumented |
| ThousandEyes Enterprise Agent | In-cluster pod, `te-demo` namespace |
| ThousandEyes Tests | 8 HTTP tests (4 in-cluster PetClinic, 4 external) |

## Scripts

| Script | Description |
|--------|-------------|
| `deploy.sh` | Full end-to-end deployment (runs all steps below) |
| `scripts/01-install-otel-collector.sh` | Install Splunk OTel Collector via Helm |
| `scripts/02-deploy-petclinic.sh` | Deploy PetClinic + patch Java instrumentation |
| `scripts/03-deploy-te-agent.sh` | Deploy ThousandEyes Enterprise Agent |
| `scripts/04-create-te-tests.sh` | Create ThousandEyes HTTP tests via API |
| `scripts/05-simulate-outage.sh` | Scale down vets/visits services for demo |
| `scripts/06-restore-services.sh` | Restore scaled-down services |
| `teardown.sh` | Remove all deployed resources |

## Demo: Simulating a Network/Service Outage

```bash
# Simulate outage (scales down vets-service + visits-service)
bash scripts/05-simulate-outage.sh

# Auto-restore after 5 minutes
DURATION=300 bash scripts/05-simulate-outage.sh
```

**What to show:**

1. **ThousandEyes** → Test Settings → filter `[your-name]`
   - `PetClinic Vets API` and `PetClinic Visits API` drop to **0% availability**
   - Error: `Connection timed out` from inside the cluster

2. **Splunk APM** → environment `${INSTANCE}-workshop`
   - `vets-service` and `visits-service` go dark
   - `api-gateway` shows upstream errors cascading

**The narrative:**
> *"ThousandEyes answers the question APM can't: is this a network problem or an application problem? Because the agent runs inside the cluster, it has the same network path as your services — giving you ground truth from your app's perspective."*

```bash
# Restore when done
bash scripts/06-restore-services.sh
```

## Finding Your ThousandEyes Agent ID

After running step 3, find your agent ID to use for test creation:

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

## Accessing the Environment

| Resource | URL |
|----------|-----|
| PetClinic app | `http://<EC2_PUBLIC_IP>:81` |
| Splunk Observability | `https://app.us1.signalfx.com` → APM → env: `${INSTANCE}-workshop` |
| ThousandEyes | `https://app.thousandeyes.com` → Test Settings → filter `[your-name]` |

## Teardown

```bash
./teardown.sh
```
