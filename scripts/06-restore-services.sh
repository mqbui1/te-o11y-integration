#!/bin/bash
# ============================================================
# Step 6: Restore services after simulated outage
# ============================================================

SERVICES="${SERVICES:-vets-service visits-service}"

echo "==> Restoring services: ${SERVICES}..."
for svc in ${SERVICES}; do
  kubectl scale deployment "${svc}" --replicas=1
  echo "    Scaled up ${svc}"
done

echo "==> Waiting for services to be ready..."
for svc in ${SERVICES}; do
  kubectl rollout status deployment/${svc} --timeout=120s
done

echo ""
echo "==> Services restored. ThousandEyes tests will show recovery within ~2 minutes."
