#!/bin/bash
# ============================================================
# Teardown: remove all deployed resources
# ============================================================

set -e

echo "==> Removing PetClinic..."
kubectl delete -f ~/workshop/petclinic/deployment.yaml --ignore-not-found

echo "==> Removing ThousandEyes agent..."
kubectl delete namespace te-demo --ignore-not-found

echo "==> Uninstalling Splunk OTel Collector..."
helm uninstall splunk-otel-collector --ignore-not-found

echo "==> Teardown complete."
