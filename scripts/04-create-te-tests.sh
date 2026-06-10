#!/bin/bash
# ============================================================
# Step 4: Create ThousandEyes tests via API
# ============================================================
# Required env vars:
#   TE_BEARER_TOKEN  - ThousandEyes user API / OAuth Bearer token
#   TE_AGENT_ID      - Enterprise Agent ID (find via GET /v7/agents)
#   TEST_PREFIX      - Prefix for test names (e.g. your-name)
#   EC2_PUBLIC_IP    - Public IP of the EC2 instance
# ============================================================

set -e

: "${TE_BEARER_TOKEN:?ERROR: TE_BEARER_TOKEN is required}"
: "${TE_AGENT_ID:?ERROR: TE_AGENT_ID is required}"
: "${TEST_PREFIX:?ERROR: TEST_PREFIX is required}"
: "${EC2_PUBLIC_IP:?ERROR: EC2_PUBLIC_IP is required}"

TE_API="https://api.thousandeyes.com/v7/tests/http-server"

create_test() {
  local name="$1"
  local url="$2"
  local result
  result=$(curl -s -X POST "${TE_API}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
    -d "{\"testName\": \"${name}\", \"url\": \"${url}\", \"interval\": 120, \"agents\": [{\"agentId\": ${TE_AGENT_ID}}], \"httpTimeLimit\": 5}")
  local id
  id=$(echo "${result}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('testId','ERROR'))" 2>/dev/null)
  echo "    Created test ID ${id}: ${name}"
}

echo "==> Creating in-cluster PetClinic tests..."
create_test "[${TEST_PREFIX}] PetClinic Frontend"     "http://api-gateway.default.svc.cluster.local:8080"
create_test "[${TEST_PREFIX}] PetClinic Owners API"   "http://customers-service.default.svc.cluster.local:8080/owners"
create_test "[${TEST_PREFIX}] PetClinic Vets API"     "http://vets-service.default.svc.cluster.local:8080/vets"
create_test "[${TEST_PREFIX}] PetClinic Visits API"   "http://visits-service.default.svc.cluster.local:8080/visits"

# ── Travel Planner agent-to-agent and agent-to-LLM tests ──────────────────────
# The TE Enterprise Agent runs inside the cluster (te-demo namespace), so it has
# the same network vantage point as the travel-planner agents themselves.
# This means TE latency/availability reflects exactly what agents experience.
echo "==> Creating in-cluster Travel Planner agent health tests..."
create_test "[${TEST_PREFIX}] Agent - Orchestrator"     "http://orchestrator.travel-planner.svc.cluster.local:8080/health"
create_test "[${TEST_PREFIX}] Agent - Flight Specialist" "http://flight-agent.travel-planner.svc.cluster.local:8080/health"
create_test "[${TEST_PREFIX}] Agent - Hotel Specialist"  "http://hotel-agent.travel-planner.svc.cluster.local:8080/health"
create_test "[${TEST_PREFIX}] Agent - Activity Specialist" "http://activity-agent.travel-planner.svc.cluster.local:8080/health"
create_test "[${TEST_PREFIX}] Agent - Synthesizer"       "http://synthesizer.travel-planner.svc.cluster.local:8080/health"

# Agent-to-LLM connectivity: TE tests the LLM provider endpoint from inside the
# cluster — the same network path the agents use. If TE sees high latency here,
# slow LLM responses in APM traces have a network-layer explanation.
echo "==> Creating agent-to-LLM connectivity tests..."
LLM_PROVIDER="${LLM_PROVIDER:-openai}"
if [ "${LLM_PROVIDER}" = "bedrock" ]; then
  AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
  create_test "[${TEST_PREFIX}] LLM - AWS Bedrock (${AWS_REGION})" \
    "https://bedrock-runtime.${AWS_REGION}.amazonaws.com"
else
  create_test "[${TEST_PREFIX}] LLM - OpenAI API" "https://api.openai.com"
fi

echo "==> Creating external tests..."
create_test "[${TEST_PREFIX}] EC2 Instance Health"          "http://${EC2_PUBLIC_IP}"
create_test "[${TEST_PREFIX}] Stripe API Health"            "https://api.stripe.com/healthcheck"
create_test "[${TEST_PREFIX}] Splunk Observability Cloud"   "https://app.us1.signalfx.com"
create_test "[${TEST_PREFIX}] ThousandEyes Platform"        "https://app.thousandeyes.com"

echo ""
echo "==> ThousandEyes tests created successfully."
echo "    View at: https://app.thousandeyes.com -> Cloud & Enterprise Agents -> Test Settings"
echo "    Filter by: [${TEST_PREFIX}]"
echo ""
echo "    Travel Planner monitoring:"
echo "      - 5 in-cluster agent health tests (agent-to-agent path)"
echo "      - 1 LLM provider connectivity test (agent-to-LLM path)"
echo "      Combined with Splunk APM LangChain traces = full observability stack"
