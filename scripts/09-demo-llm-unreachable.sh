#!/bin/bash
# ============================================================
# Demo Scenario 3: Agent-to-LLM communication failure
# ============================================================
# Simulates: all agents are reachable, but calls to the LLM
# endpoint fail. Switches to OpenAI mode with an invalid API key
# so LLM calls immediately return 401 → agent returns 500.
# Uses the real OpenAI endpoint so TE's LLM test stays green —
# confirming this is an auth/config failure, not a network failure.
#
# What ThousandEyes shows:
#   [prefix] LLM - OpenAI API → still green (api.openai.com is up)
#   All 5 agent health tests → still green (agents are reachable)
#   Key insight: TE shows it's NOT a network problem to the real
#   LLM endpoint — the issue is application-layer (bad config,
#   wrong URL, auth failure, or provider outage)
#
# What Splunk APM shows:
#   travel.plan trace: all agent.call.* spans succeed
#   LangChain spans inside each agent → ERROR (connection timeout)
#   Errors propagate: agents return fallback text, synthesizer
#   produces a degraded itinerary
#
# The story: TE gives you instant triage — "is the LLM network
# path healthy?" Yes → this is an app config issue, not network.
#
# Restore: bash scripts/10-demo-restore.sh
# ============================================================

set -e

echo "============================================================"
echo "  SCENARIO 3: Agent-to-LLM Communication Failure"
echo "  All agents reachable; LLM auth failing (instant 401)"
echo "============================================================"
echo ""

echo "==> Switching to OpenAI mode with invalid API key..."
kubectl create secret generic llm-secret \
  --namespace travel-planner \
  --from-literal=provider="openai" \
  --from-literal=api_key="sk-invalid-demo-key" \
  --from-literal=base_url="" \
  --from-literal=model="gpt-4o-mini" \
  --from-literal=bedrock_model_id="anthropic.claude-3-5-haiku-20241022-v1:0" \
  --from-literal=aws_region="us-east-1" \
  --from-literal=mock_mode="false" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Restarting specialist agents to pick up new LLM config..."
kubectl rollout restart deployment/flight-agent deployment/hotel-agent \
  deployment/activity-agent deployment/synthesizer \
  -n travel-planner
kubectl rollout status deployment/flight-agent deployment/hotel-agent \
  deployment/activity-agent deployment/synthesizer \
  -n travel-planner --timeout=120s

echo "==> Waiting for pods to fully initialize..."
sleep 10

echo "==> Triggering an immediate /plan request to surface errors now..."
kubectl run --rm -i --restart=Never llm-trigger-$$ \
  --image=curlimages/curl:latest -n travel-planner -- \
  curl -sf -X POST http://orchestrator.travel-planner.svc.cluster.local:8080/plan \
  -H "Content-Type: application/json" \
  -d '{"origin":"Seattle","destination":"Paris","travellers":2}' || true

echo ""
echo "==> Outage active."
echo ""
echo "    ThousandEyes (immediate):"
echo "      [prefix] LLM - OpenAI Status → STILL GREEN (OpenAI platform is up)"
echo "      All 5 agent health tests → STILL GREEN (agents are reachable)"
echo "      Insight: this is NOT a network failure — it's an auth/config issue"
echo "      URL: https://app.thousandeyes.com → Test Settings → filter [your-prefix]"
echo ""
echo "    Splunk APM (immediate — request just fired above):"
echo "      agent.call.* spans → all succeed (agents respond)"
echo "      LangChain spans inside agents → ERROR (AuthenticationError)"
echo "      travel.plan returns degraded result (agents return error text)"
echo "      URL: https://app.us1.signalfx.com → APM → service: flight-agent"
echo ""
echo "    Splunk Alert (~2 min):"
echo "      Detector: [Travel Planner] Scenario 3: Agent LLM Calls Failing"
echo ""
echo "    Restore: bash scripts/10-demo-restore.sh"
echo "============================================================"
