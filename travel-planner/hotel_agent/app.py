"""
Hotel Agent — specialist for hotel recommendations.

POST /invoke: recommends hotel for destination/dates.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from shared.otel_setup import register_te_middleware, setup_otel, stamp_te_span

setup_otel("hotel-agent")

from flask import Flask, jsonify, request
from opentelemetry.instrumentation.flask import FlaskInstrumentor

from shared.tools import create_llm, search_hotels

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)
register_te_middleware(app)


@app.route("/health")
def health():
    stamp_te_span()
    return jsonify({"status": "ok", "service": "hotel-agent"})


@app.route("/invoke", methods=["POST"])
def invoke():
    payload = request.get_json(force=True) or {}
    destination = payload.get("destination", "Paris")
    check_in = payload.get("check_in", "2026-08-01")
    check_out = payload.get("check_out", "2026-08-08")
    travellers = int(payload.get("travellers", 2))

    mock_result = search_hotels(destination, check_in, check_out)

    llm = create_llm()
    if llm is None:
        result = mock_result
    else:
        from langchain_core.messages import HumanMessage, SystemMessage
        response = llm.invoke([
            SystemMessage(content="You are a hotel specialist. Present the hotel recommendation concisely and professionally."),
            HumanMessage(content=f"Hotel data: {mock_result}\n\nPresent this as a recommendation for {travellers} travellers in {destination} from {check_in} to {check_out}."),
        ])
        result = response.content

    return jsonify({"result": result, "service": "hotel-agent"})
