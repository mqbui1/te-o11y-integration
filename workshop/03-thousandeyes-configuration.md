← [Module 2](./02-instrumentation-deep-dive.md) | Next: [Module 4 — Splunk Detectors & Alerting](./04-splunk-detectors-and-alerts.md) →

# Module 3: ThousandEyes Configuration (20 min)

## Why this matters

This is the "shadow network issues" story: Kubernetes service mesh and cloud networking failures are invisible to application-only monitoring. ThousandEyes solves this by running **inside the same cluster** as your services — same DNS, same routing, same egress rules your application actually experiences. This module shows you exactly how those tests are configured and why placement matters.

## Step 1: Confirm the agent placement

```bash
kubectl get pods -n te-demo -o wide
```

**Notice the NODE column** — this agent is running on the same worker node(s) as your `travel-planner` pods. This is the entire point: a synthetic test from an external PoP tells you the internet is fine. A synthetic test from inside the cluster tells you *your application's actual network path* is fine.

## Step 2: Inspect the test configuration

```bash
cat scripts/04-create-te-tests.sh
```

Find the two things that make TE tests correlate with APM:
- `"distributedTracing": true` — TE injects B3 trace headers on every request, so each test execution becomes a real span in your trace backend
- `customHeaders": {"X-TE-Test-Id": ..., "X-TE-Test-Name": ...}` — these headers are what `stamp_te_span()` (Module 2) reads to tag the resulting span

## Step 3: View your tests live

Most attendees don't have a login for the ThousandEyes web UI (it's gated behind the organizer's Cisco SSO). Instead, check status straight from the API with the token already in your shell:

```bash
bash scripts/check-te-status.sh
```

You should see:

| Test | Target |
|------|--------|
| `Agent - Orchestrator` | `/health` in-cluster |
| `Agent - Flight/Hotel/Activity Specialist` | `/health` in-cluster |
| `Agent - Synthesizer` | `/health` in-cluster |
| `LLM - OpenAI Status` | `status.openai.com` |
| `EC2 Instance Health` | external reachability |

All should show `UP` / green right now. This same command (with `--watch` appended) is what you'll use to observe outages live in Modules 5–7. (If your organizer *has* set you up with a UI login, `https://app.thousandeyes.com` → Test Settings → filter by your `TEST_PREFIX` shows the same data with more detail.)

## Step 4: Confirm distributed tracing didn't silently reset

This is a known TE API quirk worth knowing about: a partial `PUT` to the TE API can silently reset `distributedTracing` back to `false`.

```bash
TEST_ID=$(curl -s https://api.thousandeyes.com/v7/tests \
  -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
  | python3 -c "import json,sys; print(next((t['testId'] for t in json.load(sys.stdin)['tests'] if t['testName']=='[${TEST_PREFIX}] Agent - Orchestrator'), ''))")

curl -s https://api.thousandeyes.com/v7/tests/http-server/${TEST_ID} \
  -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
  | python3 -c "import json,sys; t=json.load(sys.stdin); print('distributedTracing:', t.get('distributedTracing')); print('customHeaders:', t.get('customHeaders'))"
```

(No UI needed — the first command looks up the test ID by name via the API.)

## Step 5: Set up the bi-directional drilldown (one-time, if not already done by your organizer)

- **Splunk → TE**: Settings → Global Data Links → New Link, property name `te.test.id`, URL `https://app.thousandeyes.com/view/tests/?testId={{value}}`
- **TE → Splunk**: Requires TE Account Admin — Manage → Integrations → Integrations 2.0 → Connectors → New Connector, preset "Splunk Observability APM". If you're not an Account Admin, skip this and ask your organizer whether it's already configured.

## Discussion Point

Notice this agent tests every specialist's `/health` endpoint independently, rather than one aggregate test. Why does per-service granularity matter more for a multi-agent AI system than it would for a single monolithic app?

## Troubleshooting

See repo root README → [`te.*` span attributes missing on `/health` spans](../README.md#te-span-attributes-missing-on-health-spans) and [ThousandEyes agent never appears in dashboard](../README.md#thousandeyes-agent-never-appears-in-dashboard).

---
← [Module 2](./02-instrumentation-deep-dive.md) | Next: [Module 4 — Splunk Detectors & Alerting](./04-splunk-detectors-and-alerts.md) →
