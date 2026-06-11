#!/bin/bash
# ============================================================
# Demo Scenario 3: Agent-to-LLM communication failure
# ============================================================
# Simulates: all agents are reachable, but calls to the LLM
# endpoint fail. Switches to OpenAI mode with an unreachable
# base URL (192.0.2.1 is RFC 5737 TEST-NET — guaranteed
# non-routable) so LLM calls time out without a real API key.
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
echo "  All agents reachable; LLM calls timing out"
echo "============================================================"
echo ""

echo "==> Switching to OpenAI mode with unreachable LLM endpoint..."
kubectl create secret generic llm-secret \
  --namespace travel-planner \
  --from-literal=provider="openai" \
  --from-literal=api_key="sk-demo-simulation-key" \
  --from-literal=base_url="http://192.0.2.1" \
  --from-literal=model="gpt-4o-mini" \
  --from-literal=bedrock_model_id="anthropic.claude-3-5-haiku-20241022-v1:0" \
  --from-literal=aws_region="us-east-1" \
  --from-literal=mock_mode="false" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Restarting agents to pick up new LLM config..."
kubectl rollout restart deployment/flight-agent deployment/hotel-agent \
  deployment/activity-agent deployment/synthesizer deployment/orchestrator \
  -n travel-planner
kubectl rollout status deployment/flight-agent deployment/hotel-agent \
  deployment/activity-agent deployment/synthesizer deployment/orchestrator \
  -n travel-planner --timeout=120s

echo ""
echo "==> Outage active."
echo ""
echo "    ThousandEyes (immediate):"
echo "      [prefix] LLM - OpenAI API → STILL GREEN (api.openai.com is reachable)"
echo "      All 5 agent health tests → STILL GREEN (agents are up)"
echo "      Insight: this is NOT a network failure — it's an application issue"
echo "      URL: https://app.thousandeyes.com → Test Settings → filter [your-prefix]"
echo ""
echo "    Splunk APM (on next /plan request):"
echo "      agent.call.* spans → all succeed (agents respond)"
echo "      LangChain spans inside agents → ERROR (LLM connection timeout)"
echo "      travel.plan returns degraded result (agents fall back to error text)"
echo "      URL: https://app.us1.signalfx.com → APM → service: flight-agent"
echo ""
echo "    Restore: bash scripts/10-demo-restore.sh"
echo "============================================================"
