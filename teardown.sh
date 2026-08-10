#!/bin/bash
# ============================================================
# Teardown: remove all deployed resources
# ============================================================
# Removes everything deploy.sh installs on this EC2/k3d cluster:
#   - travel-planner namespace (5 agents + load generator CronJob)
#   - te-demo namespace (ThousandEyes Enterprise Agent)
#   - splunk-otel-collector Helm release
#
# Does NOT delete cloud-side resources (ThousandEyes tests/agent
# registration, Splunk detectors) — those are matched by name and
# safely reused/updated in place the next time you run deploy.sh.
# ============================================================

set -e

echo "==> Removing Travel Planner..."
kubectl delete namespace travel-planner --ignore-not-found

echo "==> Removing ThousandEyes agent..."
kubectl delete namespace te-demo --ignore-not-found

echo "==> Uninstalling Splunk OTel Collector..."
helm uninstall splunk-otel-collector --ignore-not-found

echo "==> Teardown complete. Run ./deploy.sh to start over."
