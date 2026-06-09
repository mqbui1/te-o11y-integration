#!/bin/bash
# ============================================================
# Step 3: Deploy ThousandEyes Enterprise Agent in Kubernetes
# ============================================================
# Required env vars:
#   TE_ACCOUNT_TOKEN  - ThousandEyes Account Group Token
#   AGENT_HOSTNAME    - Unique hostname for agent (e.g. your-name)
#                       Appears in the ThousandEyes dashboard
# ============================================================

set -e

: "${TE_ACCOUNT_TOKEN:?ERROR: TE_ACCOUNT_TOKEN is required}"
: "${AGENT_HOSTNAME:?ERROR: AGENT_HOSTNAME is required}"

echo "==> Creating te-demo namespace..."
kubectl create namespace te-demo --dry-run=client -o yaml | kubectl apply -f -

echo "==> Creating ThousandEyes credentials secret..."
TE_TOKEN_B64=$(echo -n "${TE_ACCOUNT_TOKEN}" | base64)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: te-creds
  namespace: te-demo
type: Opaque
data:
  TEAGENT_ACCOUNT_TOKEN: ${TE_TOKEN_B64}
EOF

echo "==> Deploying ThousandEyes Enterprise Agent (hostname: te-agent-${AGENT_HOSTNAME})..."
sed "s/\${AGENT_HOSTNAME}/${AGENT_HOSTNAME}/g" \
  "$(dirname "$0")/../manifests/thousandEyesDeploy.yaml" | kubectl apply -f -

echo "==> Waiting for ThousandEyes agent pod to be ready..."
kubectl rollout status deployment/thousandeyes -n te-demo --timeout=180s

echo ""
echo "==> ThousandEyes Enterprise Agent deployed successfully."
echo "    Agent name: te-agent-${AGENT_HOSTNAME}"
echo "    Verify at:  https://app.thousandeyes.com -> Cloud & Enterprise Agents -> Agent Settings"
