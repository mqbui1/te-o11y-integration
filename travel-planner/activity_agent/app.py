"""
Activity Agent — specialist for destination experiences.

POST /invoke: curates activities and experiences for a destination.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from shared.otel_setup import setup_otel

setup_otel("activity-agent")

from flask import Flask, jsonify, request
from opentelemetry.instrumentation.flask import FlaskInstrumentor

from shared.tools import create_llm, search_activities

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app, excluded_urls="/health")


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "activity-agent"})


@app.route("/invoke", methods=["POST"])
def invoke():
    payload = request.get_json(force=True) or {}
    destination = payload.get("destination", "Paris")
    travellers = int(payload.get("travellers", 2))

    mock_result = search_activities(destination)

    llm = create_llm()
    if llm is None:
        result = mock_result
    else:
        from langchain_core.messages import HumanMessage, SystemMessage
        response = llm.invoke([
            SystemMessage(content="You are an activity specialist. Curate and present experiences engagingly."),
            HumanMessage(content=f"Available experiences: {mock_result}\n\nPresent these as curated recommendations for {travellers} travellers spending a week in {destination}."),
        ])
        result = response.content

    return jsonify({"result": result, "service": "activity-agent"})
