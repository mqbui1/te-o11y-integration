#!/bin/bash
# ============================================================
# Step 4: Create ThousandEyes tests via API
# ============================================================
# Required env vars:
#   TE_BEARER_TOKEN  - ThousandEyes OAuth Bearer token
#   TE_AGENT_ID      - Enterprise Agent ID (find via GET /v7/agents)
#   TEST_PREFIX      - Prefix for test names (e.g. your-name)
#   EC2_PUBLIC_IP    - Public IP of the EC2 instance
#
# Optional env vars:
#   AGENT_HOSTNAME   - Used to set TE_AGENT_NAME in ConfigMap (defaults to TEST_PREFIX)
#   LLM_PROVIDER     - openai (default) or bedrock
#
# Distributed Tracing (bi-directional APM ↔ ThousandEyes drilldowns):
#   Travel planner agent tests are created with distributedTracing=true so
#   ThousandEyes injects B3 trace headers into each test request. This creates
#   a real distributed trace visible in Splunk APM, and the Splunk APM Connector
#   in ThousandEyes enables a "View in APM" link from each test result.
#
#   After creating tests, this script writes test IDs and names into the
#   te-test-ids ConfigMap in the travel-planner namespace, and restarts the
#   orchestrator. This populates APM spans with te.test.name / te.test.id /
#   te.test.url attributes — enabling "View in ThousandEyes" from APM spans.
#
# Splunk APM Connector (required for TE → APM direction):
#   This is a one-time manual setup in ThousandEyes UI:
#   1. In Splunk, create an Access Token with API scope
#   2. ThousandEyes: Manage → Integrations → Integrations 2.0 → Connectors tab
#   3. Create Generic Connector, Preset: "Splunk Observability APM"
#      - Name: Splunk APM
#      - Target URL: https://api.<REALM>.signalfx.com
#      - Header: X-SF-Token: <api-scope-token>
#   4. Save & Assign Operation → New Operation → "Splunk Observability APM"
#   See: https://docs.thousandeyes.com/product-documentation/integration-guides/
#        custom-built-integrations/distributed-tracing/distributed-tracing-splunk-apm
# ============================================================

set -e

: "${TE_BEARER_TOKEN:?ERROR: TE_BEARER_TOKEN is required}"
: "${TE_AGENT_ID:?ERROR: TE_AGENT_ID is required}"
: "${TEST_PREFIX:?ERROR: TEST_PREFIX is required}"
: "${EC2_PUBLIC_IP:?ERROR: EC2_PUBLIC_IP is required}"

TE_API="https://api.thousandeyes.com/v7/tests/http-server"
AGENT_HOSTNAME="${AGENT_HOSTNAME:-${TEST_PREFIX}}"

# create_or_get_test NAME URL [DISTRIBUTED_TRACING]
# Creates the test if it doesn't exist, or fetches the ID if it already does.
# Returns the test ID via stdout; prints status to stderr.
create_test() {
  local name="$1"
  local url="$2"
  local distributed_tracing="${3:-false}"
  local body
  body=$(printf '{"testName":"%s","url":"%s","interval":120,"agents":[{"agentId":%d}],"httpTimeLimit":5,"distributedTracing":%s}' \
    "${name}" "${url}" "${TE_AGENT_ID}" "${distributed_tracing}")
  local result
  result=$(curl -s -X POST "${TE_API}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
    -d "${body}")
  local id
  id=$(echo "${result}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('testId',''))" 2>/dev/null)

  # If creation failed (test already exists), look up the existing test ID
  if [ -z "${id}" ]; then
    id=$(curl -s "https://api.thousandeyes.com/v7/tests" \
      -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
      | _TE_TEST_NAME="${name}" python3 -c "
import json, sys, os
name = os.environ.get('_TE_TEST_NAME', '')
tests = json.load(sys.stdin).get('tests', [])
match = next((t for t in tests if t.get('testName') == name), None)
print(match['testId'] if match else '')
" 2>/dev/null)
    echo "    Existing test ID ${id:-ERROR}: ${name}" >&2
  else
    echo "    Created test ID ${id}: ${name}" >&2
  fi
  echo "${id}"
}

echo "==> Creating in-cluster PetClinic tests..."
create_test "[${TEST_PREFIX}] PetClinic Frontend"     "http://api-gateway.default.svc.cluster.local:8080"     "true" > /dev/null
create_test "[${TEST_PREFIX}] PetClinic Owners API"   "http://customers-service.default.svc.cluster.local:8080/owners" "true" > /dev/null
create_test "[${TEST_PREFIX}] PetClinic Vets API"     "http://vets-service.default.svc.cluster.local:8080/vets"     "true" > /dev/null
create_test "[${TEST_PREFIX}] PetClinic Visits API"   "http://visits-service.default.svc.cluster.local:8080/visits"  "true" > /dev/null

# ── Travel Planner agent health tests (distributed tracing enabled) ────────────
# distributedTracing=true: ThousandEyes injects B3 trace headers into each
# request. The app extracts them (B3 propagator configured in otel_setup.py)
# and continues the trace — these requests appear in Splunk APM as child spans
# of a TE root span, enabling bi-directional APM ↔ ThousandEyes drilldowns.
echo "==> Creating in-cluster Travel Planner agent health tests (distributed tracing enabled)..."
FLIGHT_TEST_NAME="[${TEST_PREFIX}] Agent - Flight Specialist"
HOTEL_TEST_NAME="[${TEST_PREFIX}] Agent - Hotel Specialist"
ACTIVITY_TEST_NAME="[${TEST_PREFIX}] Agent - Activity Specialist"
SYNTH_TEST_NAME="[${TEST_PREFIX}] Agent - Synthesizer"

FLIGHT_TEST_ID=$(create_test   "${FLIGHT_TEST_NAME}"   "http://flight-agent.travel-planner.svc.cluster.local:8080/health"   "true")
HOTEL_TEST_ID=$(create_test    "${HOTEL_TEST_NAME}"    "http://hotel-agent.travel-planner.svc.cluster.local:8080/health"    "true")
ACTIVITY_TEST_ID=$(create_test "${ACTIVITY_TEST_NAME}" "http://activity-agent.travel-planner.svc.cluster.local:8080/health" "true")
SYNTH_TEST_ID=$(create_test    "${SYNTH_TEST_NAME}"    "http://synthesizer.travel-planner.svc.cluster.local:8080/health"    "true")
# Orchestrator test (for /health monitoring; orchestrator is the root span origin)
create_test "[${TEST_PREFIX}] Agent - Orchestrator" "http://orchestrator.travel-planner.svc.cluster.local:8080/health" "true" > /dev/null

# ── Write test IDs back to ConfigMap ──────────────────────────────────────────
# The orchestrator reads these at startup and stamps each agent call span with
# te.test.name, te.test.id, te.test.url — visible in Splunk APM span detail.
echo "==> Updating te-test-ids ConfigMap in travel-planner namespace..."
kubectl create configmap te-test-ids \
  --namespace travel-planner \
  --from-literal=TE_AGENT_NAME="te-agent-${AGENT_HOSTNAME}" \
  --from-literal=TE_TEST_NAME_FLIGHT="${FLIGHT_TEST_NAME}" \
  --from-literal=TE_TEST_ID_FLIGHT="${FLIGHT_TEST_ID}" \
  --from-literal=TE_TEST_NAME_HOTEL="${HOTEL_TEST_NAME}" \
  --from-literal=TE_TEST_ID_HOTEL="${HOTEL_TEST_ID}" \
  --from-literal=TE_TEST_NAME_ACTIVITY="${ACTIVITY_TEST_NAME}" \
  --from-literal=TE_TEST_ID_ACTIVITY="${ACTIVITY_TEST_ID}" \
  --from-literal=TE_TEST_NAME_SYNTH="${SYNTH_TEST_NAME}" \
  --from-literal=TE_TEST_ID_SYNTH="${SYNTH_TEST_ID}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Restarting orchestrator to pick up new test IDs..."
kubectl rollout restart deployment/orchestrator -n travel-planner
kubectl rollout status deployment/orchestrator -n travel-planner --timeout=120s

# Agent-to-LLM connectivity: TE tests the LLM provider endpoint from inside the
# cluster — the same network path the agents use. If TE sees high latency here,
# slow LLM responses in APM traces have a network-layer explanation.
echo "==> Creating agent-to-LLM connectivity tests..."
LLM_PROVIDER="${LLM_PROVIDER:-openai}"
if [ "${LLM_PROVIDER}" = "bedrock" ]; then
  AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
  create_test "[${TEST_PREFIX}] LLM - AWS Bedrock (${AWS_REGION})" \
    "https://bedrock-runtime.${AWS_REGION}.amazonaws.com" "false" > /dev/null
else
  create_test "[${TEST_PREFIX}] LLM - OpenAI API" "https://api.openai.com" "false" > /dev/null
fi

echo "==> Creating external tests..."
create_test "[${TEST_PREFIX}] EC2 Instance Health"          "http://${EC2_PUBLIC_IP}"              "false" > /dev/null
create_test "[${TEST_PREFIX}] Stripe API Health"            "https://api.stripe.com/healthcheck"  "false" > /dev/null
create_test "[${TEST_PREFIX}] Splunk Observability Cloud"   "https://app.us1.signalfx.com"        "false" > /dev/null
create_test "[${TEST_PREFIX}] ThousandEyes Platform"        "https://app.thousandeyes.com"         "false" > /dev/null

echo ""
echo "==> ThousandEyes tests created and APM correlation configured."
echo "    View tests: https://app.thousandeyes.com -> Network & App Synthetics -> Test Settings"
echo "    Filter by:  [${TEST_PREFIX}]"
echo ""
echo "    Distributed tracing (bi-directional drilldowns):"
echo "      TE  → APM: Each agent test has distributedTracing=true."
echo "                 TE injects B3 headers; requests appear as root spans in Splunk APM."
echo "                 Requires Splunk APM Connector in ThousandEyes (one-time manual setup)."
echo "      APM → TE:  Orchestrator spans now carry te.test.name / te.test.id / te.test.url."
echo "                 Visible in Splunk APM span detail for every agent call."
echo ""
echo "    Splunk APM Connector (if not already set up):"
echo "      ThousandEyes: Manage → Integrations → Integrations 2.0 → Connectors"
echo "      → Generic Connector, Preset: Splunk Observability APM"
echo "      → Target URL: https://api.<REALM>.signalfx.com"
echo "      → Header: X-SF-Token: <api-scope-token>"
