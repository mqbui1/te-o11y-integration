"""
Flight Agent — specialist for flight search.

POST /invoke: finds best flight option for origin/destination/date.
Uses LLM to format results if configured, otherwise returns mock data directly.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from shared.otel_setup import setup_otel

setup_otel("flight-agent")

from flask import Flask, jsonify, request
from opentelemetry.instrumentation.flask import FlaskInstrumentor

from shared.tools import create_llm, search_flights

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "flight-agent"})


@app.route("/invoke", methods=["POST"])
def invoke():
    payload = request.get_json(force=True) or {}
    origin = payload.get("origin", "Seattle")
    destination = payload.get("destination", "Paris")
    departure = payload.get("departure", "2026-08-01")

    mock_result = search_flights(origin, destination, departure)

    travellers = int(payload.get("travellers", 2))
    llm = create_llm()
    if llm is None:
        result = mock_result
    else:
        from langchain_core.messages import HumanMessage, SystemMessage
        response = llm.invoke([
            SystemMessage(content="You are a flight specialist. Present the flight option concisely and professionally."),
            HumanMessage(content=f"Flight data: {mock_result}\n\nPresent this as a recommendation for {travellers} travellers from {origin} to {destination} on {departure}."),
        ])
        result = response.content

    return jsonify({"result": result, "service": "flight-agent"})
