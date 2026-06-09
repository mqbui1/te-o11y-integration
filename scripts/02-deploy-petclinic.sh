#!/bin/bash
# ============================================================
# Step 2: Deploy PetClinic microservices + enable Java auto-instrumentation
# ============================================================

set -e

echo "==> Deploying PetClinic application..."
kubectl apply -f ~/workshop/petclinic/deployment.yaml

echo "==> Waiting for core services to start..."
kubectl rollout status deployment/config-server --timeout=120s
kubectl rollout status deployment/discovery-server --timeout=120s
kubectl rollout status deployment/petclinic-db --timeout=120s

echo "==> Patching deployments with Java auto-instrumentation annotation..."
for svc in api-gateway customers-service vets-service visits-service admin-server; do
  kubectl patch deployment "${svc}" --patch \
    '{"spec":{"template":{"metadata":{"annotations":{"instrumentation.opentelemetry.io/inject-java":"default/splunk-otel-collector"}}}}}'
  echo "    Patched ${svc}"
done

echo "==> Waiting for instrumented services to be ready..."
for svc in api-gateway customers-service vets-service visits-service; do
  kubectl rollout status deployment/${svc} --timeout=180s
done

echo ""
echo "==> PetClinic deployed and instrumented successfully."
echo "    Access the app at: http://$(curl -s ifconfig.me):81"
echo "    APM environment:   ${INSTANCE}-workshop"
