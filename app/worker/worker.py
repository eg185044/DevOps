import os
import time
import datetime
from flask import Flask, jsonify, request, Response
from prometheus_client import Counter, Histogram, Gauge, CONTENT_TYPE_LATEST, generate_latest

app = Flask(__name__)

def env(name, default=""):
    return os.environ.get(name, default)

# See app/backend/app.py for the full rationale (same pattern, same
# cardinality rules) - kept intentionally lighter here since the worker
# has far fewer routes.
REQUEST_COUNT = Counter(
    "worker_http_requests_total",
    "Total HTTP requests handled by the worker",
    ["method", "endpoint", "http_status"],
)
REQUEST_ERRORS = Counter(
    "worker_http_request_errors_total",
    "HTTP requests that resulted in a 5xx response",
    ["method", "endpoint"],
)
REQUEST_LATENCY = Histogram(
    "worker_http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)
APP_INFO = Gauge(
    "worker_app_info",
    "Static info about the running build (value is always 1; the labels carry the data)",
    ["version", "git_sha", "release"],
)
APP_INFO.labels(
    version=env("APP_VERSION", "unknown"),
    git_sha=env("APP_GIT_SHA", "unknown"),
    release=env("APP_RELEASE", env("ENVIRONMENT", "unknown")),
).set(1)


@app.before_request
def _start_timer():
    request._prom_start_time = time.perf_counter()


@app.after_request
def _record_metrics(response):
    endpoint = request.url_rule.rule if request.url_rule else "unmatched"
    method = request.method
    status = str(response.status_code)

    REQUEST_COUNT.labels(method=method, endpoint=endpoint, http_status=status).inc()
    if response.status_code >= 500:
        REQUEST_ERRORS.labels(method=method, endpoint=endpoint).inc()

    start = getattr(request, "_prom_start_time", None)
    if start is not None:
        REQUEST_LATENCY.labels(method=method, endpoint=endpoint).observe(time.perf_counter() - start)

    return response


@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.route("/health")
def health():
    return jsonify({
        "service": "worker",
        "status": "ok",
        "time": datetime.datetime.utcnow().isoformat() + "Z",
        "bucket": env("S3_BUCKET_NAME", "not-configured")
    })

@app.route("/")
def index():
    return jsonify({"service": "worker", "message": "Background worker is running"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(env("WORKER_PORT", "5002")))
