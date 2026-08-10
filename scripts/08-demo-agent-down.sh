#!/bin/bash
# ============================================================
# Demo Scenario 2: Agent-to-agent communication failure
# ============================================================
# Simulates: orchestrator is healthy, but the flight specialist agent
# is unreachable — a common partial failure in multi-agent systems.
#
# Usage:
#   bash scripts/08-demo-agent-down.sh
#
# What ThousandEyes shows:
#   [prefix] Agent - Flight Specialist → availability drops to 0%
#   All other agent tests remain green
#   Proves the issue is isolated to flight-agent's network path
#
# What Splunk APM shows:
#   travel.plan trace completes (orchestrator still works)
#   agent.call.flight-agent span → ERROR (connection refused)
#   te.test.id on the failing span → "View in ThousandEyes" button
#   Other agent.call.* spans remain healthy
#
# Restore: bash scripts/10-demo-restore.sh
# ============================================================

set -e

AGENT="flight-agent"
TE_TEST_NAME="Agent - Flight Specialist"

echo "============================================================"
echo "  SCENARIO 2: Agent-to-Agent Communication Failure"
echo "  Agent down: ${AGENT}"
echo "============================================================"
echo ""

echo "==> Scaling ${AGENT} to 0 replicas..."
kubectl scale deployment "${AGENT}" --replicas=0 -n travel-planner

echo ""
echo "==> Outage active."
echo ""
echo "    ThousandEyes (~2 min to reflect):"
echo "      Failing test: [prefix] ${TE_TEST_NAME}"
echo "      All other agent tests: remain green"
echo "      This proves the failure is isolated to ${AGENT}'s path"
echo "      URL: https://app.thousandeyes.com → Test Settings → filter [your-prefix]"
echo ""
echo "    Splunk APM (immediate on next /plan request):"
echo "      Service: orchestrator → operation: travel.plan"
echo "      Failing span: agent.call.${AGENT} → ERROR"
echo "      Click te.test.id on that span → View in ThousandEyes button"
echo "      Other agent spans (hotel, activity, synthesizer): healthy"
echo "      URL: https://app.us1.signalfx.com → APM → service: orchestrator"
echo ""
echo "    Restore: bash scripts/10-demo-restore.sh"
echo "============================================================"
