#!/bin/bash
# ============================================================
# Restore: reset all travel planner demo scenarios
# ============================================================
# Restores all agents to 1 replica and resets LLM config to
# mock mode. Safe to run after any of scenarios 1, 2, or 3.
# ============================================================

set -e

echo "============================================================"
echo "  Restoring Travel Planner to normal operation"
echo "============================================================"
echo ""

echo "==> Restoring all agent replicas to 1..."
kubectl scale deployment orchestrator flight-agent hotel-agent \
  activity-agent synthesizer --replicas=1 -n travel-planner

echo "==> Resetting LLM config to mock mode..."
kubectl create secret generic llm-secret \
  --namespace travel-planner \
  --from-literal=provider="mock" \
  --from-literal=api_key="none" \
  --from-literal=base_url="" \
  --from-literal=model="gpt-4o-mini" \
  --from-literal=bedrock_model_id="anthropic.claude-3-5-haiku-20241022-v1:0" \
  --from-literal=aws_region="us-east-1" \
  --from-literal=mock_mode="true" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Restarting all agents to pick up restored config..."
kubectl rollout restart deployment/orchestrator deployment/flight-agent \
  deployment/hotel-agent deployment/activity-agent deployment/synthesizer \
  -n travel-planner
kubectl rollout status deployment/orchestrator deployment/flight-agent \
  deployment/hotel-agent deployment/activity-agent deployment/synthesizer \
  -n travel-planner --timeout=120s

echo ""
echo "==> All services restored."
echo ""
echo "    ThousandEyes: all tests should return to green within ~2 minutes"
echo "    Splunk APM:   healthy travel.plan traces resume immediately"
echo "============================================================"
