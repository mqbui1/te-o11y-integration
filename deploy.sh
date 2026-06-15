#!/bin/bash
# ============================================================
# ThousandEyes + Splunk Observability Integration
# Full automated deployment script
# ============================================================
# Usage:
#   export TE_ACCOUNT_TOKEN="your-te-account-group-token"
#   export TE_BEARER_TOKEN="your-te-api-bearer-token"
#   export AGENT_HOSTNAME="your-name"     # appears in TE dashboard
#   export TEST_PREFIX="your-name"        # prefix for TE test names
#   export TE_AGENT_ID=""                 # set after step 3 completes
#   ./deploy.sh
#
# The following are pre-set on Splunk workshop EC2 instances:
#   ACCESS_TOKEN, REALM, INSTANCE, HEC_URL, HEC_TOKEN, RUM_FRONTEND_IP
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/scripts" && pwd)"

# ── Validate required inputs ──────────────────────────────────
: "${TE_BEARER_TOKEN:?ERROR: Set TE_BEARER_TOKEN (ThousandEyes API Bearer Token)}"

# Auto-fetch TE_ACCOUNT_TOKEN if not provided (03-deploy-te-agent.sh will also attempt this)
if [ -z "${TE_ACCOUNT_TOKEN}" ]; then
  echo "==> TE_ACCOUNT_TOKEN not set — fetching from API using TE_BEARER_TOKEN..."
  TE_AG_AID=$(curl -s https://api.thousandeyes.com/v7/account-groups \
    -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
    | python3 -c "
import json, sys
ags = json.load(sys.stdin).get('accountGroups', [])
current = [ag for ag in ags if ag.get('isCurrentAccountGroup')]
ag = current[0] if current else (ags[0] if ags else None)
print(ag['aid'] if ag else '')
" 2>/dev/null)
  if [ -n "${TE_AG_AID}" ]; then
    TE_ACCOUNT_TOKEN=$(curl -s "https://api.thousandeyes.com/v7/account-groups/${TE_AG_AID}" \
      -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
      | python3 -c "
import json, sys
print(json.load(sys.stdin).get('accountToken', ''))
" 2>/dev/null)
  fi
  [ -n "${TE_ACCOUNT_TOKEN}" ] && echo "==> TE_ACCOUNT_TOKEN fetched." || echo "==> TE_ACCOUNT_TOKEN will be fetched by deploy-te-agent step."
  export TE_ACCOUNT_TOKEN
fi
: "${AGENT_HOSTNAME:?ERROR: Set AGENT_HOSTNAME (unique name for TE agent, e.g. your-name)}"
: "${TEST_PREFIX:=${AGENT_HOSTNAME}}"

# Splunk vars from EC2 /etc/environment
: "${ACCESS_TOKEN:?ERROR: ACCESS_TOKEN not set (should be in /etc/environment)}"
: "${REALM:?ERROR: REALM not set (should be in /etc/environment)}"
: "${INSTANCE:?ERROR: INSTANCE not set (should be in /etc/environment)}"

EC2_PUBLIC_IP="${RUM_FRONTEND_IP:-$(curl -s ifconfig.me)}"

echo "============================================================"
echo "  ThousandEyes + Splunk O11y Integration - Deploy"
echo "============================================================"
echo "  Instance:       ${INSTANCE}"
echo "  Environment:    ${INSTANCE}-workshop"
echo "  Realm:          ${REALM}"
echo "  Agent hostname: te-agent-${AGENT_HOSTNAME}"
echo "  EC2 public IP:  ${EC2_PUBLIC_IP}"
echo "============================================================"
echo ""

# ── Step 1: Splunk OTel Collector ─────────────────────────────
echo "[ 1/5 ] Installing Splunk OTel Collector..."
bash "${SCRIPT_DIR}/01-install-otel-collector.sh"
echo ""

# ── Step 2: Travel Planner ────────────────────────────────────
echo "[ 2/5 ] Deploying Travel Planner AI agents..."
LLM_PROVIDER="${LLM_PROVIDER:-mock}" bash "${SCRIPT_DIR}/02-deploy-travel-planner.sh"
echo ""

# ── Step 3: ThousandEyes Agent ────────────────────────────────
echo "[ 3/5 ] Deploying ThousandEyes Enterprise Agent..."
bash "${SCRIPT_DIR}/03-deploy-te-agent.sh"
echo ""

# ── Step 4: ThousandEyes Tests ────────────────────────────────
echo "[ 4/5 ] Creating ThousandEyes tests..."
echo ""
echo "  To find your TE_AGENT_ID, run:"
echo "    curl -s https://api.thousandeyes.com/v7/agents \\"
echo "      -H 'Authorization: Bearer \${TE_BEARER_TOKEN}' \\"
echo "      | python3 -c \"import json,sys; [print(a['agentId'], a['agentName']) for a in json.load(sys.stdin)['agents'] if '${AGENT_HOSTNAME}' in a['agentName']]\""
echo ""

if [ -z "${TE_AGENT_ID}" ]; then
  echo "  TE_AGENT_ID not set — looking it up automatically..."
  TE_AGENT_ID=$(curl -s https://api.thousandeyes.com/v7/agents \
    -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
    | python3 -c "
import json, sys
agents = json.load(sys.stdin).get('agents', [])
match = [a['agentId'] for a in agents if '${AGENT_HOSTNAME}' in a.get('agentName','') and a.get('agentState') == 'online']
print(match[0] if match else '')
" 2>/dev/null)

  if [ -z "${TE_AGENT_ID}" ]; then
    echo "  WARNING: Could not auto-detect agent ID. Agent may not be online yet."
    echo "  Set TE_AGENT_ID manually and re-run: bash scripts/04-create-te-tests.sh"
  else
    echo "  Found agent ID: ${TE_AGENT_ID}"
    export TE_AGENT_ID
    export EC2_PUBLIC_IP
    bash "${SCRIPT_DIR}/04-create-te-tests.sh"
  fi
else
  export EC2_PUBLIC_IP
  bash "${SCRIPT_DIR}/04-create-te-tests.sh"
fi

# ── Step 5: Splunk Detectors ──────────────────────────────────
echo ""
echo "[ 5/5 ] Creating Splunk Observability detectors..."
if [ -z "${SPLUNK_API_TOKEN:-}" ] && [ -z "${ACCESS_TOKEN:-}" ]; then
  echo "  Skipping: set SPLUNK_API_TOKEN (API-scoped) to create detectors automatically."
  echo "  Re-run manually:  SPLUNK_API_TOKEN=<token> bash scripts/05-create-splunk-detectors.sh"
else
  bash "${SCRIPT_DIR}/05-create-splunk-detectors.sh"
fi

echo ""
echo "============================================================"
echo "  Deployment complete!"
echo "============================================================"
echo "  Travel Planner:     kubectl run -it --rm test --image=curlimages/curl --restart=Never -n travel-planner -- \\"
echo "                        curl -X POST http://orchestrator.travel-planner.svc.cluster.local:8080/plan \\"
echo "                          -H 'Content-Type: application/json' \\"
echo "                          -d '{\"origin\": \"Seattle\", \"destination\": \"Paris\"}'"
echo "  Splunk APM:         https://app.${REALM}.signalfx.com"
echo "    -> Environment:   ${INSTANCE}-workshop"
echo "  ThousandEyes:       https://app.thousandeyes.com"
echo "    -> Filter tests:  [${TEST_PREFIX}]"
echo ""
echo "  Demo scenarios:     bash scripts/07-demo-orchestrator-down.sh"
echo "                      bash scripts/08-demo-agent-down.sh"
echo "                      bash scripts/09-demo-llm-unreachable.sh"
echo "  Restore:            bash scripts/10-demo-restore.sh"
echo "============================================================"
