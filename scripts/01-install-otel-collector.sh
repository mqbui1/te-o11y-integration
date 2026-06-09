#!/bin/bash
# ============================================================
# Step 1: Install Splunk OpenTelemetry Collector via Helm
# ============================================================
# Required env vars (pre-set on Splunk workshop EC2 instances):
#   ACCESS_TOKEN  - Splunk Observability ingest token
#   REALM         - Splunk realm (e.g. us1)
#   INSTANCE      - Workshop instance name (e.g. teo11y-2b93)
#   HEC_URL       - Splunk HEC endpoint URL
#   HEC_TOKEN     - Splunk HEC token
# ============================================================

set -e

OTEL_CHART_VERSION="${OTEL_CHART_VERSION:-0.136.0}"

echo "==> Adding Splunk OTel Collector Helm repo..."
helm repo add splunk-otel-collector-chart https://signalfx.github.io/splunk-otel-collector-chart
helm repo update

echo "==> Creating workshop-secret..."
kubectl create secret generic workshop-secret \
  --from-literal=env="${INSTANCE}-workshop" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing Splunk OTel Collector v${OTEL_CHART_VERSION}..."
helm upgrade --install splunk-otel-collector \
  --version "${OTEL_CHART_VERSION}" \
  --set="operatorcrds.install=true" \
  --set="operator.enabled=true" \
  --set="splunkObservability.realm=${REALM}" \
  --set="splunkObservability.accessToken=${ACCESS_TOKEN}" \
  --set="clusterName=${INSTANCE}-k3s-cluster" \
  --set="splunkObservability.profilingEnabled=true" \
  --set="agent.service.enabled=true" \
  --set="environment=${INSTANCE}-workshop" \
  --set="splunkPlatform.endpoint=${HEC_URL}" \
  --set="splunkPlatform.token=${HEC_TOKEN}" \
  --set="splunkPlatform.index=splunk4rookies-workshop" \
  splunk-otel-collector-chart/splunk-otel-collector \
  -f ~/workshop/k3s/otel-collector.yaml

echo "==> Waiting for OTel Collector pods to be ready..."
kubectl rollout status deployment/splunk-otel-collector-operator --timeout=120s
kubectl rollout status daemonset/splunk-otel-collector-agent --timeout=120s

echo "==> Splunk OTel Collector installed successfully."
echo "    Environment: ${INSTANCE}-workshop"
echo "    Realm:       ${REALM}"
