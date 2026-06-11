"""Shared OpenTelemetry setup for all travel-planner services."""
import os

from opentelemetry import _events, _logs, metrics, propagate, trace
from opentelemetry.baggage.propagation import W3CBaggagePropagator
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.langchain import LangchainInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.propagators.b3 import B3Format
from opentelemetry.propagators.composite import CompositePropagator
from opentelemetry.sdk._events import EventLoggerProvider
from opentelemetry.sdk._logs import LoggerProvider
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.trace.sampling import ALWAYS_ON, ParentBased
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator


def setup_otel(service_name: str) -> None:
    """
    Initialize OTel SDK for a travel-planner microservice.

    Reads OTEL_EXPORTER_OTLP_ENDPOINT from the environment (set via the
    Splunk OTel Collector DaemonSet hostIP pattern in K8s manifests).

    Propagators are set in the order required for ThousandEyes distributed
    tracing: baggage → b3 → tracecontext. This ensures TE-injected B3 headers
    are extracted correctly so TE-initiated requests appear as root spans in
    Splunk APM with bi-directional drilldown support.

    ParentBased(ALWAYS_ON) sampler ensures traces started by ThousandEyes
    synthetic tests are always sampled and appear in Splunk APM.
    """
    # Propagators: baggage → b3 → tracecontext (order matters for TE integration)
    propagate.set_global_textmap(CompositePropagator([
        W3CBaggagePropagator(),
        B3Format(),
        TraceContextTextMapPropagator(),
    ]))

    resource = Resource.create(
        {
            SERVICE_NAME: os.environ.get("OTEL_SERVICE_NAME", service_name),
            "deployment.environment": os.environ.get(
                "DEPLOYMENT_ENVIRONMENT", "travel-planner-demo"
            ),
        }
    )

    # ParentBased(ALWAYS_ON): continues sampling when TE starts the trace
    tracer_provider = TracerProvider(resource=resource, sampler=ParentBased(ALWAYS_ON))
    tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(tracer_provider)

    # Metrics
    metric_reader = PeriodicExportingMetricReader(OTLPMetricExporter())
    metrics.set_meter_provider(
        MeterProvider(resource=resource, metric_readers=[metric_reader])
    )

    # Logs
    log_provider = LoggerProvider(resource=resource)
    log_provider.add_log_record_processor(BatchLogRecordProcessor(OTLPLogExporter()))
    _logs.set_logger_provider(log_provider)
    _events.set_event_logger_provider(EventLoggerProvider())

    # Instrumentations — LangChain spans + outbound HTTP context propagation
    LangchainInstrumentor().instrument()
    RequestsInstrumentor().instrument()


def register_te_middleware(app) -> None:
    """
    Register a Flask before_request hook that reads ThousandEyes custom headers
    (X-TE-Test-Id, X-TE-Test-Name) injected by TE HTTP tests and stamps them
    onto the current span. This makes /health spans (and any TE-hit endpoint)
    show te.test.* correlation tags in Splunk APM just like the orchestrator's
    agent.call.* spans do.

    TE tests must be configured to send these headers — see 04-create-te-tests.sh.
    """
    from flask import request as flask_request

    @app.before_request
    def _stamp_te_headers():
        te_test_id = flask_request.headers.get("X-TE-Test-Id", "")
        te_test_name = flask_request.headers.get("X-TE-Test-Name", "")
        if te_test_id or te_test_name:
            span = trace.get_current_span()
            if te_test_id:
                span.set_attribute("te.test.id", te_test_id)
                span.set_attribute("te.test.url",
                    f"https://app.thousandeyes.com/view/tests/?testId={te_test_id}")
            if te_test_name:
                span.set_attribute("te.test.name", te_test_name)
