"""
Orchestrator service — entry point for travel planning.

Receives POST /plan, calls each specialist agent via HTTP in sequence,
then calls the synthesizer. OTel trace context is propagated automatically
by RequestsInstrumentor (W3C TraceContext headers), so all agent spans
appear as children of this root span in Splunk APM.

ThousandEyes correlation:
  Each agent call span is annotated with the corresponding TE test name and ID
  so that a failing APM span links directly to the TE test that monitors the
  same network path. Set via TE_TEST_* env vars (injected from te-test-ids
  ConfigMap by the deployment manifest).

  Span tags added per agent call:
    te.test.name   — TE test name, e.g. "[prefix] Agent - Flight Specialist"
    te.test.id     — TE test ID (integer), for direct API/UI lookup
    te.test.url    — Deep link into ThousandEyes UI for that test
    te.agent.name  — TE Enterprise Agent running the test

  When a call fails, an additional tag is set:
    te.correlation — human-readable hint to check TE for network root cause
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from shared.otel_setup import register_te_middleware, setup_otel, stamp_te_span

setup_otel("orchestrator")

from datetime import datetime, timedelta

import requests
from flask import Flask, jsonify, request
from opentelemetry import trace
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.trace import SpanKind, StatusCode

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)
register_te_middleware(app)

# Service URLs — use K8s ClusterIP DNS names, overridable via env
FLIGHT_AGENT_URL   = os.environ.get("FLIGHT_AGENT_URL",   "http://flight-agent.travel-planner.svc.cluster.local:8080")
HOTEL_AGENT_URL    = os.environ.get("HOTEL_AGENT_URL",    "http://hotel-agent.travel-planner.svc.cluster.local:8080")
ACTIVITY_AGENT_URL = os.environ.get("ACTIVITY_AGENT_URL", "http://activity-agent.travel-planner.svc.cluster.local:8080")
SYNTHESIZER_URL    = os.environ.get("SYNTHESIZER_URL",    "http://synthesizer.travel-planner.svc.cluster.local:8080")

# ThousandEyes test metadata — injected from te-test-ids ConfigMap
# Maps each agent to its TE test name + ID so APM spans link back to TE tests
TE_AGENT_NAME = os.environ.get("TE_AGENT_NAME", "")
TE_TESTS = {
    "flight-agent":    {"name": os.environ.get("TE_TEST_NAME_FLIGHT",   ""), "id": os.environ.get("TE_TEST_ID_FLIGHT",   "")},
    "hotel-agent":     {"name": os.environ.get("TE_TEST_NAME_HOTEL",    ""), "id": os.environ.get("TE_TEST_ID_HOTEL",    "")},
    "activity-agent":  {"name": os.environ.get("TE_TEST_NAME_ACTIVITY", ""), "id": os.environ.get("TE_TEST_ID_ACTIVITY", "")},
    "synthesizer":     {"name": os.environ.get("TE_TEST_NAME_SYNTH",    ""), "id": os.environ.get("TE_TEST_ID_SYNTH",    "")},
}

tracer = trace.get_tracer(__name__)


def _dates_from_now(days_out: int = 30, duration: int = 7):
    start = datetime.now() + timedelta(days=days_out)
    end = start + timedelta(days=duration)
    return start.strftime("%Y-%m-%d"), end.strftime("%Y-%m-%d")


def _call_agent(agent_key: str, url: str, payload: dict, timeout: int = 30):
    """
    Call a downstream agent and annotate the current span with ThousandEyes
    test metadata so APM failures link directly to the corresponding TE test.
    """
    te = TE_TESTS.get(agent_key, {})
    te_test_id = te.get("id", "")
    te_test_name = te.get("name", "")

    with tracer.start_as_current_span(f"agent.call.{agent_key}", kind=SpanKind.CLIENT) as span:
        span.set_attribute("agent.name", agent_key)

        # ThousandEyes correlation tags — visible in Splunk APM span detail
        if te_test_name:
            span.set_attribute("te.test.name", te_test_name)
        if te_test_id:
            span.set_attribute("te.test.id", te_test_id)
            span.set_attribute("te.test.url",
                f"https://app.thousandeyes.com/view/tests/?testId={te_test_id}")
        if TE_AGENT_NAME:
            span.set_attribute("te.agent.name", TE_AGENT_NAME)

        try:
            resp = requests.post(url, json=payload, timeout=timeout)
            resp.raise_for_status()
            span.set_attribute("http.status_code", resp.status_code)
            return resp.json().get("result", "")
        except Exception as e:
            span.set_status(StatusCode.ERROR, str(e))
            # Hint in the span that TE data can explain the network root cause
            if te_test_name:
                span.set_attribute("te.correlation",
                    f"Check TE test '{te_test_name}' for network-layer root cause")
            raise


@app.route("/health")
def health():
    stamp_te_span()
    return jsonify({"status": "ok", "service": "orchestrator"})


@app.route("/plan", methods=["POST"])
def plan():
    payload = request.get_json(force=True) or {}
    origin      = payload.get("origin", "Seattle")
    destination = payload.get("destination", "Paris")
    travellers  = int(payload.get("travellers", 2))
    departure, return_date = _dates_from_now()

    with tracer.start_as_current_span("travel.plan", kind=SpanKind.SERVER) as span:
        span.set_attribute("travel.origin", origin)
        span.set_attribute("travel.destination", destination)
        span.set_attribute("travel.travellers", travellers)
        span.set_attribute("travel.departure", departure)

        errors = []

        try:
            flight_result = _call_agent("flight-agent", f"{FLIGHT_AGENT_URL}/invoke",
                {"origin": origin, "destination": destination, "departure": departure})
        except Exception as e:
            flight_result = "Flight info unavailable"
            errors.append(f"flight-agent: {e}")

        try:
            hotel_result = _call_agent("hotel-agent", f"{HOTEL_AGENT_URL}/invoke",
                {"destination": destination, "check_in": departure, "check_out": return_date})
        except Exception as e:
            hotel_result = "Hotel info unavailable"
            errors.append(f"hotel-agent: {e}")

        try:
            activity_result = _call_agent("activity-agent", f"{ACTIVITY_AGENT_URL}/invoke",
                {"destination": destination})
        except Exception as e:
            activity_result = "Activity info unavailable"
            errors.append(f"activity-agent: {e}")

        try:
            itinerary = _call_agent("synthesizer", f"{SYNTHESIZER_URL}/invoke", {
                "origin": origin, "destination": destination,
                "departure": departure, "return_date": return_date,
                "travellers": travellers, "flight_summary": flight_result,
                "hotel_summary": hotel_result, "activities_summary": activity_result,
            }, timeout=60)
        except Exception as e:
            itinerary = f"Synthesis failed: {e}"
            errors.append(f"synthesizer: {e}")

        if errors:
            span.set_attribute("travel.errors", ", ".join(errors))

        return jsonify({
            "origin": origin, "destination": destination,
            "departure": departure, "return_date": return_date,
            "travellers": travellers, "flight_summary": flight_result,
            "hotel_summary": hotel_result, "activities_summary": activity_result,
            "itinerary": itinerary,
        })
