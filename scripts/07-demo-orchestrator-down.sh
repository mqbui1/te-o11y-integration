#!/bin/bash
# ============================================================
# Demo Scenario 1: Orchestrator unreachable
# ============================================================
# Simulates: user prompt never reaches the AI system.
# The entry point (orchestrator) is scaled to zero.
#
# What ThousandEyes shows:
#   [prefix] Agent - Orchestrator → availability drops to 0%
#   Connection refused / timeout from te-agent-*
#   Exact failure timestamp visible in availability chart
#
# What Splunk APM shows:
#   No new travel.plan traces appear (nothing gets in)
#   Existing traces continue from load generator until they fail
#
# Restore: bash scripts/10-demo-restore.sh
# ============================================================

set -e

echo "============================================================"
echo "  SCENARIO 1: Orchestrator Down"
echo "  User prompts cannot reach the AI system"
echo "============================================================"
echo ""

echo "==> Scaling orchestrator to 0 replicas..."
kubectl scale deployment orchestrator --replicas=0 -n travel-planner

echo ""
echo "==> Outage active."
echo ""
echo "    ThousandEyes (~2 min to reflect):"
echo "      Test: [prefix] Agent - Orchestrator"
echo "      Expected: availability → 0%, connection refused"
echo "      URL: https://app.thousandeyes.com → Test Settings → filter [your-prefix]"
echo ""
echo "    Splunk APM (immediate):"
echo "      No new travel.plan traces appear"
echo "      Service map: orchestrator goes dark"
echo "      URL: https://app.us1.signalfx.com → APM → service: orchestrator"
echo ""
echo "    Restore: bash scripts/10-demo-restore.sh"
echo "============================================================"
