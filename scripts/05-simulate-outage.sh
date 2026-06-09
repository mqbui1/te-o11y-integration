#!/bin/bash
# ============================================================
# Step 5: Simulate service outage for demo
# ============================================================
# Scales down vets-service and visits-service to trigger
# ThousandEyes availability alerts and APM error spikes.
# Run 06-restore-services.sh to recover.
# ============================================================

SERVICES="${SERVICES:-vets-service visits-service}"
DURATION="${DURATION:-}"

echo "==> Simulating outage: scaling down ${SERVICES}..."
for svc in ${SERVICES}; do
  kubectl scale deployment "${svc}" --replicas=0
  echo "    Scaled down ${svc}"
done

echo ""
echo "==> Outage active. What to show:"
echo "    1. ThousandEyes: tests for Vets API and Visits API will show 0% availability"
echo "       -> app.thousandeyes.com -> Test Settings -> filter by your prefix"
echo "    2. Splunk APM: vets-service and visits-service go dark, api-gateway shows upstream errors"
echo "       -> app.us1.signalfx.com -> APM -> environment: ${INSTANCE}-workshop"
echo ""

if [ -n "${DURATION}" ]; then
  echo "==> Auto-restoring in ${DURATION} seconds..."
  sleep "${DURATION}"
  bash "$(dirname "$0")/06-restore-services.sh"
else
  echo "==> Run ./scripts/06-restore-services.sh when ready to restore."
fi
