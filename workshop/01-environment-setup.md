← [Agenda](./AGENDA.md) | Next: [Module 2 — Instrumentation Deep-Dive](./02-instrumentation-deep-dive.md) →

# Module 1: Environment & Architecture (20 min)

## Why this matters

Before you can trust what an observability stack tells you during an incident, you need to know what it actually touches. This module deploys the full pipeline and walks the architecture — so every later module is inspecting a system you understand, not a black box.

**Value to keep in mind:** notice as you deploy that there's no secondary agent, no separate data pipeline to maintain — one OTel Collector handles traces, metrics, and logs for every service.

## Step 1: Set your identity

Pick something unique to you so your resources don't collide with other participants on the same shared ThousandEyes/Splunk accounts.

```bash
export TE_BEARER_TOKEN="your-oauth-bearer-token"
export AGENT_HOSTNAME="your-name"     # becomes te-agent-your-name in TE dashboard
export TEST_PREFIX="your-name"        # prefix for all TE test names
export LLM_PROVIDER=mock              # no LLM key needed for this workshop
```

## Step 2: Deploy

```bash
cd te-o11y-integration
chmod +x deploy.sh scripts/*.sh
./deploy.sh
```

This runs five steps in order — watch the terminal output for each:

1. Splunk OTel Collector (Helm chart — DaemonSet agent + cluster receiver)
2. Travel Planner (5 Flask AI agents + load generator CronJob)
3. ThousandEyes Enterprise Agent (deployed **inside** the cluster — this is the differentiator, not an external probe)
4. ThousandEyes tests (5 agent health checks + LLM + external reachability)
5. Splunk detectors (skipped if `SPLUNK_API_TOKEN` isn't set — see Module 4)

Takes ~8–12 minutes. While it runs, read the architecture diagram in the repo root [`README.md`](../README.md#architecture).

## Step 3: Verify

```bash
kubectl get deployments -n travel-planner
# All 5 should show 1/1 READY

kubectl get pods -n te-demo
# thousandeyes agent should be Running
```

## Step 4: Generate a baseline trace manually

```bash
kubectl run -it --rm test --image=curlimages/curl --restart=Never -n travel-planner -- \
  curl -X POST http://orchestrator.travel-planner.svc.cluster.local:8080/plan \
    -H 'Content-Type: application/json' \
    -d '{"origin": "Seattle", "destination": "Paris", "travellers": 2}'
```

You should get back a JSON itinerary. This request is now a trace in Splunk APM.

## Step 5: Find yourself in Splunk APM

Go to `https://app.us1.signalfx.com` → APM → filter environment to `<INSTANCE>-workshop` (your organizer will tell you the instance name). Find the `travel.plan` trace you just generated.

**What to notice:** five spans, one per service, all green. This is your baseline — every scenario later in this workshop is a variation on breaking one part of this picture.

## Discussion Point

Before moving on, ask yourself: in your own environment, how many services would a single AI request actually touch? Is it closer to 5, or closer to 50? Does the triage problem get easier or harder as that number grows?

## Troubleshooting

See repo root README → [Troubleshooting](../README.md#troubleshooting), especially "ThousandEyes agent never appears in dashboard" and "Travel planner pods in CrashLoopBackOff".

---
← [Agenda](./AGENDA.md) | Next: [Module 2 — Instrumentation Deep-Dive](./02-instrumentation-deep-dive.md) →
