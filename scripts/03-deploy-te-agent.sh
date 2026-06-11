#!/bin/bash
# ============================================================
# Step 3: Deploy ThousandEyes Enterprise Agent in Kubernetes
# ============================================================
#
# THOUSANDEYES TOKEN GUIDE — there are three distinct tokens:
#
#   TE_BEARER_TOKEN    OAuth2 Bearer token for API calls (create tests, list agents).
#                      Found at: app.thousandeyes.com → Account Settings →
#                      Users and Roles → User API Tokens → "OAuth Bearer Token"
#                      Format: UUID  e.g. 1cd116ac-7ee2-4eb4-b2ae-96de3c3923df
#
#   TE_ACCOUNT_TOKEN   Account Group Token — used by the Enterprise Agent to
#                      register itself with the ThousandEyes platform.
#                      Found at: Cloud & Enterprise Agents → Agent Settings →
#                      Add New Enterprise Agent (shown on Step 1 of wizard)
#                      Format: 32-char alphanumeric  e.g. uvrolnzpmdc06e79qcy6...
#
#                      *** If not provided, this script auto-fetches it from the
#                      API using TE_BEARER_TOKEN. You only need to set one. ***
#
#   User API Token     Legacy Basic-auth token (32-char alphanumeric). Used for
#                      API calls in older integrations. NOT the Account Group Token
#                      even though they look similar. Do not use this for agents.
#
# Required env vars:
#   TE_BEARER_TOKEN   - OAuth2 Bearer token (always required for API calls)
#   AGENT_HOSTNAME    - Unique name suffix for the agent (e.g. your-name)
#                       Agent appears in dashboard as te-agent-<AGENT_HOSTNAME>
#
# Optional env vars:
#   TE_ACCOUNT_TOKEN  - Account Group Token (auto-fetched from API if not set)
# ============================================================

set -e

: "${TE_BEARER_TOKEN:?ERROR: TE_BEARER_TOKEN (OAuth Bearer) is required}"
: "${AGENT_HOSTNAME:?ERROR: AGENT_HOSTNAME is required}"

# ── Auto-fetch Account Group Token if not explicitly provided ─────────────────
if [ -z "${TE_ACCOUNT_TOKEN}" ]; then
  echo "==> TE_ACCOUNT_TOKEN not set — fetching from API using TE_BEARER_TOKEN..."
  TE_ACCOUNT_TOKEN=$(curl -s https://api.thousandeyes.com/v7/account-groups \
    -H "Authorization: Bearer ${TE_BEARER_TOKEN}" \
    | python3 -c "
import json, sys
ags = json.load(sys.stdin).get('accountGroups', [])
# Prefer the current/default account group
current = [ag for ag in ags if ag.get('isCurrentAccountGroup')]
ag = current[0] if current else (ags[0] if ags else None)
if ag:
    token = ag.get('accountToken', '')
    if token:
        print(token)
        import sys; sys.stderr.write('  Account Group: ' + ag['accountGroupName'] + '\n')
    else:
        sys.stderr.write('ERROR: accountToken not in response\n')
        sys.exit(1)
else:
    sys.stderr.write('ERROR: no account groups found\n')
    sys.exit(1)
" 2>&1 | tee /dev/stderr | grep -v "Account Group\|ERROR")

  if [ -z "${TE_ACCOUNT_TOKEN}" ]; then
    echo "ERROR: Could not auto-fetch Account Group Token."
    echo "  Set TE_ACCOUNT_TOKEN manually:"
    echo "  app.thousandeyes.com → Cloud & Enterprise Agents → Agent Settings → Add New Enterprise Agent"
    exit 1
  fi
  echo "  Account Group Token fetched successfully."
fi

# ── Deploy ────────────────────────────────────────────────────────────────────
echo "==> Creating te-demo namespace..."
kubectl create namespace te-demo --dry-run=client -o yaml | kubectl apply -f -

echo "==> Creating ThousandEyes credentials secret..."
kubectl create secret generic te-creds \
  --namespace te-demo \
  --from-literal=TEAGENT_ACCOUNT_TOKEN="${TE_ACCOUNT_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Deploying ThousandEyes Enterprise Agent (hostname: te-agent-${AGENT_HOSTNAME})..."
sed "s/\${AGENT_HOSTNAME}/${AGENT_HOSTNAME}/g" \
  "$(dirname "$0")/../manifests/thousandEyesDeploy.yaml" | kubectl apply -f -

echo "==> Waiting for ThousandEyes agent pod to be ready..."
kubectl rollout status deployment/thousandeyes -n te-demo --timeout=180s

echo ""
echo "==> ThousandEyes Enterprise Agent deployed successfully."
echo "    Agent name: te-agent-${AGENT_HOSTNAME}"
echo "    Verify at:  https://app.thousandeyes.com -> Cloud & Enterprise Agents -> Agent Settings"
echo "    Note: agent registration takes 2-3 minutes after pod starts."
