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

echo "==> Creating external tests..."
create_test "[${TEST_PREFIX}] EC2 Instance Health"          "http://${EC2_PUBLIC_IP}"
create_test "[${TEST_PREFIX}] Stripe API Health"            "https://api.stripe.com/healthcheck"
create_test "[${TEST_PREFIX}] Splunk Observability Cloud"   "https://app.us1.signalfx.com"
create_test "[${TEST_PREFIX}] ThousandEyes Platform"        "https://app.thousandeyes.com"

echo ""
echo "==> ThousandEyes tests created successfully."
echo "    View at: https://app.thousandeyes.com -> Cloud & Enterprise Agents -> Test Settings"
echo "    Filter by: [${TEST_PREFIX}]"
