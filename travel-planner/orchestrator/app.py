"""
Orchestrator service — entry point for travel planning.

Receives POST /plan, calls each specialist agent via HTTP in sequence,
then calls the synthesizer. OTel trace context is propagated automatically
by RequestsInstrumentor (W3C TraceContext headers), so all agent spans
appear as children of this root span in Splunk APM.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from shared.otel_setup import setup_otel

setup_otel("orchestrator")

from datetime import datetime, timedelta

import requests
from flask import Flask, jsonify, request
from opentelemetry import trace
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.trace import SpanKind

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app, excluded_urls="/health")

# Service URLs — use K8s ClusterIP DNS names, overridable via env
FLIGHT_AGENT_URL = os.environ.get("FLIGHT_AGENT_URL", "http://flight-agent.travel-planner.svc.cluster.local:8080")
HOTEL_AGENT_URL = os.environ.get("HOTEL_AGENT_URL", "http://hotel-agent.travel-planner.svc.cluster.local:8080")
ACTIVITY_AGENT_URL = os.environ.get("ACTIVITY_AGENT_URL", "http://activity-agent.travel-planner.svc.cluster.local:8080")
SYNTHESIZER_URL = os.environ.get("SYNTHESIZER_URL", "http://synthesizer.travel-planner.svc.cluster.local:8080")

tracer = trace.get_tracer(__name__)


def _dates_from_now(days_out: int = 30, duration: int = 7):
    start = datetime.now() + timedelta(days=days_out)
    end = start + timedelta(days=duration)
    return start.strftime("%Y-%m-%d"), end.strftime("%Y-%m-%d")


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "orchestrator"})


@app.route("/plan", methods=["POST"])
def plan():
    payload = request.get_json(force=True) or {}
    origin = payload.get("origin", "Seattle")
    destination = payload.get("destination", "Paris")
    travellers = int(payload.get("travellers", 2))
    departure, return_date = _dates_from_now()

    with tracer.start_as_current_span("travel.plan", kind=SpanKind.SERVER) as span:
        span.set_attribute("travel.origin", origin)
        span.set_attribute("travel.destination", destination)
        span.set_attribute("travel.travellers", travellers)
        span.set_attribute("travel.departure", departure)

        errors = []

        # Call each specialist agent — RequestsInstrumentor propagates trace context
        try:
            flight_resp = requests.post(
                f"{FLIGHT_AGENT_URL}/invoke",
                json={"origin": origin, "destination": destination, "departure": departure},
                timeout=30,
            )
            flight_result = flight_resp.json().get("result", "Flight info unavailable")
        except Exception as e:
            flight_result = "Flight info unavailable"
            errors.append(f"flight-agent: {e}")

        try:
            hotel_resp = requests.post(
                f"{HOTEL_AGENT_URL}/invoke",
                json={"destination": destination, "check_in": departure, "check_out": return_date},
                timeout=30,
            )
            hotel_result = hotel_resp.json().get("result", "Hotel info unavailable")
        except Exception as e:
            hotel_result = "Hotel info unavailable"
            errors.append(f"hotel-agent: {e}")

        try:
            activity_resp = requests.post(
                f"{ACTIVITY_AGENT_URL}/invoke",
                json={"destination": destination},
                timeout=30,
            )
            activity_result = activity_resp.json().get("result", "Activity info unavailable")
        except Exception as e:
            activity_result = "Activity info unavailable"
            errors.append(f"activity-agent: {e}")

        try:
            synth_resp = requests.post(
                f"{SYNTHESIZER_URL}/invoke",
                json={
                    "origin": origin,
                    "destination": destination,
                    "departure": departure,
                    "return_date": return_date,
                    "travellers": travellers,
                    "flight_summary": flight_result,
                    "hotel_summary": hotel_result,
                    "activities_summary": activity_result,
                },
                timeout=60,
            )
            itinerary = synth_resp.json().get("result", "Itinerary unavailable")
        except Exception as e:
            itinerary = f"Synthesis failed: {e}"
            errors.append(f"synthesizer: {e}")

        if errors:
            span.set_attribute("travel.errors", ", ".join(errors))

        return jsonify({
            "origin": origin,
            "destination": destination,
            "departure": departure,
            "return_date": return_date,
            "travellers": travellers,
            "flight_summary": flight_result,
            "hotel_summary": hotel_result,
            "activities_summary": activity_result,
            "itinerary": itinerary,
        })
