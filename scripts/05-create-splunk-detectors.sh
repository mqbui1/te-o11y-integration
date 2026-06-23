#!/bin/bash
# ============================================================
# Step 5: Create Splunk Observability detectors for Travel Planner demo
# ============================================================
# Creates three detectors for the ThousandEyes + Splunk APM demo:
#   Scenario 1 — Orchestrator Unreachable
#   Scenario 2 — Specialist Agent Unreachable (one rule per agent)
#   Scenario 3 — Agent LLM Calls Failing
#
# Idempotent: if a detector with the same name already exists it is
# updated in-place (PUT), not duplicated.
#
# Required env vars (pre-set on workshop EC2 instances):
#   REALM         - Splunk realm (e.g. us1)
#   INSTANCE      - Workshop instance name (e.g. o11yte-ea0a)
#                   Detectors filter on environment: ${INSTANCE}-workshop
#
# Token (one of the following, in priority order):
#   SPLUNK_API_TOKEN  - API-scoped token (can create/update detectors)
#   ACCESS_TOKEN      - Falls back to this if SPLUNK_API_TOKEN is not set.
#                       Note: workshop EC2 ACCESS_TOKEN is ingest-only and
#                       will return 401. Set SPLUNK_API_TOKEN explicitly:
#                         export SPLUNK_API_TOKEN="<api-scope-token>"
#                         bash scripts/05-create-splunk-detectors.sh
#
# TE test IDs are read from the te-test-ids ConfigMap (populated by
# 04-create-te-tests.sh). The script falls back to empty strings if a
# key is missing — alerts still fire, but the TE links will be absent.
# ============================================================

set -e

: "${REALM:?ERROR: REALM is required (set in /etc/environment on workshop EC2)}"
: "${INSTANCE:?ERROR: INSTANCE is required (set in /etc/environment on workshop EC2)}"

# Prefer an explicit API token; fall back to the ingest ACCESS_TOKEN
ACCESS_TOKEN="${SPLUNK_API_TOKEN:-${ACCESS_TOKEN:-}}"
: "${ACCESS_TOKEN:?ERROR: Set SPLUNK_API_TOKEN (API-scoped) or ACCESS_TOKEN}"

ENV="${INSTANCE}-workshop"

echo "============================================================"
echo "  Creating Splunk detectors"
echo "  Environment: ${ENV}"
echo "============================================================"

# ── Read TE test IDs from ConfigMap ──────────────────────────────────────────
_cm() { kubectl get configmap te-test-ids -n travel-planner \
  -o jsonpath="{.data.$1}" 2>/dev/null || echo ""; }

TE_ID_ORCH=$(_cm TE_TEST_ID_ORCH)
TE_ID_FLIGHT=$(_cm TE_TEST_ID_FLIGHT)
TE_ID_HOTEL=$(_cm TE_TEST_ID_HOTEL)
TE_ID_ACTIVITY=$(_cm TE_TEST_ID_ACTIVITY)
TE_ID_SYNTH=$(_cm TE_TEST_ID_SYNTH)
TE_ID_LLM=$(_cm TE_TEST_ID_LLM)

echo "  TE test IDs from ConfigMap:"
echo "    Orchestrator: ${TE_ID_ORCH:-<not set>}"
echo "    Flight:       ${TE_ID_FLIGHT:-<not set>}"
echo "    Hotel:        ${TE_ID_HOTEL:-<not set>}"
echo "    Activity:     ${TE_ID_ACTIVITY:-<not set>}"
echo "    Synthesizer:  ${TE_ID_SYNTH:-<not set>}"
echo "    LLM:          ${TE_ID_LLM:-<not set>}"
echo ""

# ── Create / update detectors via Python ─────────────────────────────────────
python3 - \
  "${ACCESS_TOKEN}" "${REALM}" "${ENV}" \
  "${TE_ID_ORCH}" "${TE_ID_FLIGHT}" "${TE_ID_HOTEL}" \
  "${TE_ID_ACTIVITY}" "${TE_ID_SYNTH}" "${TE_ID_LLM}" << 'PYEOF'
import json, sys, urllib.request, urllib.error

(ACCESS_TOKEN, REALM, ENV,
 TE_ORCH, TE_FLIGHT, TE_HOTEL,
 TE_ACTIVITY, TE_SYNTH, TE_LLM) = sys.argv[1:]

API    = f"https://api.{REALM}.signalfx.com/v2"
HDRS   = {"X-SF-Token": ACCESS_TOKEN, "Content-Type": "application/json"}
TE_URL = "https://app.thousandeyes.com/view/tests/?testId={}"


def api(method, path, body=None):
    data = json.dumps(body).encode() if body else None
    req  = urllib.request.Request(f"{API}{path}", data=data,
                                  method=method, headers=HDRS)
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        print(f"  ERROR {e.code}: {e.read().decode()[:300]}", file=sys.stderr)
        return None


def existing_id(name):
    """Return detector ID if a detector with this name already exists."""
    page = api("GET", "/detector?limit=100") or {}
    return next((d["id"] for d in page.get("results", [])
                 if d["name"] == name), None)


def upsert(payload):
    name = payload["name"]
    det_id = existing_id(name)
    if det_id:
        api("PUT", f"/detector/{det_id}", payload)
        print(f"    Updated  {det_id}: {name}")
    else:
        result = api("POST", "/detector", payload)
        if result:
            print(f"    Created  {result['id']}: {name}")


def te_link(test_id, label):
    """Return a formatted ThousandEyes link line, or a placeholder."""
    if test_id:
        return f"{label}:\n{TE_URL.format(test_id)}"
    return f"{label}: (test ID not available — re-run 04-create-te-tests.sh)"


# ── Scenario 1: Orchestrator Unreachable ─────────────────────────────────────
name1 = f"[Travel Planner] Scenario 1: Orchestrator Unreachable ({ENV})"
body1 = f"""{{{{severity}}}} alert — {{{{detectorName}}}}

The entry point to the AI Travel Planner is unreachable.
The orchestrator is not accepting connections — no travel plans are being processed.

Incident:   {{{{incidentId}}}}
Time:       {{{{timestamp}}}}

━━━ Network Triage (ThousandEyes) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{te_link(TE_ORCH, f"[{ENV}] Agent - Orchestrator")}

\u2022 Network HEALTHY  \u2192 Orchestrator pod is down or crashlooping.
                     kubectl logs -n travel-planner deployment/orchestrator
\u2022 Network DEGRADED \u2192 Network path to the entry point is broken.
                     Check Kubernetes DNS and cluster networking.

━━━ Application Triage (Splunk APM) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Service:    orchestrator
Operation:  travel.plan
Symptom:    No new traces \u2014 service map goes dark. Load generator still running.

━━━ Detection Logic ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

requests = data('http.server.duration_count', filter=filter('service.name', 'orchestrator') and filter('deployment.environment', '{ENV}') and filter('http.method', 'POST'), rollup='sum', extrapolation='zero', maxExtrapolations=5).sum().sum(over='2m')
detect(when(requests == 0), off=when(requests > 0, lasting='1m')).publish('orchestrator_down')"""

prog1 = f"""requests = data('http.server.duration_count', filter=filter('service.name', 'orchestrator') and filter('deployment.environment', '{ENV}') and filter('http.method', 'POST'), rollup='sum', extrapolation='zero', maxExtrapolations=5).sum().sum(over='2m')
detect(when(requests == 0), off=when(requests > 0, lasting='1m')).publish('orchestrator_down')"""

print("==> Scenario 1: Orchestrator Unreachable")
upsert({
    "name": name1,
    "description": "Fires when orchestrator /plan receives zero requests for 2 minutes",
    "programText": prog1,
    "rules": [{
        "severity": "Critical",
        "detectLabel": "orchestrator_down",
        "name": "Orchestrator unreachable",
        "description": "No /plan requests for 2 minutes",
        "parameterizedBody": body1,
        "notifications": []
    }]
})

# ── Scenario 2: Specialist Agent Unreachable ──────────────────────────────────
agents = [
    ("flight-agent",    TE_FLIGHT,   "Flight Specialist"),
    ("hotel-agent",     TE_HOTEL,    "Hotel Specialist"),
    ("activity-agent",  TE_ACTIVITY, "Activity Specialist"),
    ("synthesizer",     TE_SYNTH,    "Synthesizer"),
]

# Orchestrator health stream (shared across all rules)
prog_lines = [
    f"orch = data('http.server.duration_count', filter=filter('service.name', 'orchestrator') and filter('deployment.environment', '{ENV}') and filter('http.method', 'POST'), rollup='sum', extrapolation='zero', maxExtrapolations=5).sum().sum(over='2m')",
]
rules2     = []
for svc, te_id, label in agents:
    var = svc.replace("-", "_")
    prog_lines += [
        f"{var} = data('http.server.duration_count', filter=filter('service.name', '{svc}') and filter('deployment.environment', '{ENV}') and filter('http.method', 'POST'), rollup='sum', extrapolation='zero', maxExtrapolations=5).sum().sum(over='2m')",
        f"detect(when(orch > 0 and {var} == 0), off=when({var} > 0, lasting='1m')).publish('{var}_down')",
    ]
    rule_body = f"""{{{{severity}}}} alert — {{{{detectorName}}}}

The {label} agent is unreachable. The orchestrator cannot call this specialist.
Travel plans will complete with degraded output for the affected component.

Incident:   {{{{incidentId}}}}
Time:       {{{{timestamp}}}}

━━━ Network Triage (ThousandEyes) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{te_link(te_id, f"[{ENV}] Agent - {label}")}

\u2022 Network HEALTHY  \u2192 Agent pod is down or crashlooping.
                     kubectl logs -n travel-planner deployment/{svc}
\u2022 Network DEGRADED \u2192 Network path from orchestrator to this agent is broken.

━━━ Application Triage (Splunk APM) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Service:    orchestrator
Operation:  agent.call.{svc}
Symptom:    ERROR span (connection refused). Click te.test.id on the span
            to open \u201cView in ThousandEyes\u201d. Other agent spans remain healthy.
            travel.plan trace completes with fallback content.

━━━ Detection Logic ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

orch = data('http.server.duration_count', filter=filter('service.name', 'orchestrator')...).sum().sum(over='2m')
{var} = data('http.server.duration_count', filter=filter('service.name', '{svc}')...).sum().sum(over='2m')
detect(when(orch > 0 and {var} == 0), off=when({var} > 0, lasting='1m')).publish('{var}_down')
Note: only fires when orchestrator is healthy — avoids cascade from Scenario 1."""

    rules2.append({
        "severity": "Critical",
        "detectLabel": f"{var}_down",
        "name": f"{label} unreachable",
        "description": f"No requests to {svc} for 2 minutes (while orchestrator is healthy)",
        "parameterizedBody": rule_body,
        "notifications": []
    })

name2 = f"[Travel Planner] Scenario 2: Specialist Agent Unreachable ({ENV})"
print("==> Scenario 2: Specialist Agent Unreachable")
upsert({
    "name": name2,
    "description": "Fires when a specialist agent gets no requests while orchestrator is healthy",
    "programText": "\n".join(prog_lines),
    "rules": rules2
})

# ── Scenario 3: Agent LLM Calls Failing ──────────────────────────────────────
name3 = f"[Travel Planner] Scenario 3: Agent LLM Calls Failing ({ENV})"
body3 = f"""{{{{severity}}}} alert — {{{{detectorName}}}}

AI agents in the Travel Planner are returning 5xx errors on their LLM calls.
All agents may be affected. Travel plans are returning degraded output.

Incident:   {{{{incidentId}}}}
Time:       {{{{timestamp}}}}

━━━ Network Triage (ThousandEyes) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{te_link(TE_LLM, f"[{ENV}] LLM - OpenAI Status (status.openai.com)")}

\u2022 Network HEALTHY  \u2192 Application-layer issue. Check LLM base_url, API key, or
                     provider config. Look for openai.APITimeoutError in APM
                     spans (~31s duration, 3 retries at 10s timeout each).
\u2022 Network DEGRADED \u2192 Egress routing or firewall blocking LLM traffic.

━━━ Application Triage (Splunk APM) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Services:   flight-agent, hotel-agent, activity-agent, synthesizer
Operation:  POST /invoke
Symptom:    HTTP 500. Span duration ~31s. Exception: openai.APITimeoutError
            All four agents fail simultaneously. orchestrator travel.plan
            trace completes with degraded/fallback content.

━━━ Detection Logic ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

errors = data('http.server.duration_count', filter=filter('service.name', 'flight-agent', 'hotel-agent', 'activity-agent', 'synthesizer') and filter('deployment.environment', '{ENV}') and filter('http.status_code', '500', '502', '503'), rollup='sum', extrapolation='zero', maxExtrapolations=-1).sum().sum(over='2m')
detect(when(errors > 0), off=when(errors == 0, lasting='1m')).publish('llm_errors')"""

prog3 = f"""errors = data('http.server.duration_count', filter=filter('service.name', 'flight-agent', 'hotel-agent', 'activity-agent', 'synthesizer') and filter('deployment.environment', '{ENV}') and filter('http.status_code', '500', '502', '503'), rollup='sum', extrapolation='zero', maxExtrapolations=-1).sum().sum(over='2m')
detect(when(errors > 0), off=when(errors == 0, lasting='1m')).publish('llm_errors')"""

print("==> Scenario 3: Agent LLM Calls Failing")
upsert({
    "name": name3,
    "description": "Fires when 5xx errors accumulate on specialist agents over a 2-minute window",
    "programText": prog3,
    "rules": [{
        "severity": "Critical",
        "detectLabel": "llm_errors",
        "name": "Agent LLM calls failing",
        "description": "5xx errors from specialist agents",
        "parameterizedBody": body3,
        "notifications": []
    }]
})

print("")
print("Detectors created/updated successfully.")
print(f"View at: https://app.{REALM}.signalfx.com -> Alerts -> Detectors")
PYEOF

echo ""
echo "============================================================"
echo "  Detectors ready."
echo "  Add notification recipients in Splunk:"
echo "  Alerts -> Detectors -> [Travel Planner] Scenario * -> Edit -> Notifications"
echo "============================================================"
