import os
import time
import datetime
from flask import Flask, jsonify, request, Response
import boto3
import psycopg2
from prometheus_client import Counter, Histogram, Gauge, CONTENT_TYPE_LATEST, generate_latest

app = Flask(__name__)

def env(name, default=""):
    return os.environ.get(name, default)

# --- Prometheus instrumentation ------------------------------------------
# /metrics is a separate endpoint from /health (liveness/readiness) - it is
# never used as a probe target and is only reachable from the scrape path
# authorized by observability/network-policies/ (Prometheus in the
# observability namespace), never from the public Ingress.
#
# Cardinality is bounded deliberately: `endpoint` is the Flask *route rule*
# (e.g. "/db/events"), never request.path, so no raw URL, user ID, or
# request ID ever becomes a label value - see observability/README.md
# "Cardinality".
REQUEST_COUNT = Counter(
    "backend_http_requests_total",
    "Total HTTP requests handled by the backend",
    ["method", "endpoint", "http_status"],
)
REQUEST_ERRORS = Counter(
    "backend_http_request_errors_total",
    "HTTP requests that resulted in a 5xx response",
    ["method", "endpoint"],
)
REQUEST_LATENCY = Histogram(
    "backend_http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)
# One business metric: how many times the CV has actually been served -
# the one action this whole platform exists to perform.
CV_VIEWS = Counter(
    "backend_cv_views_total",
    "Number of times the CV payload (/cv) was successfully served",
)
# app_info is the traceability hinge the final project asks for: from a
# commit -> CI build -> image tag(=git SHA) -> this gauge's label -> the
# Grafana panel that shows exactly which version is running right now.
APP_INFO = Gauge(
    "backend_app_info",
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
    # request.url_rule.rule is the route *pattern* ("/db/events"), not the
    # resolved path - stable, low-cardinality label even if the app grows
    # path parameters later. Unmatched paths (404s) are labeled "unmatched"
    # rather than the raw path, for the same cardinality reason.
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
    return jsonify({"service": "backend", "status": "ok", "time": datetime.datetime.utcnow().isoformat() + "Z"})

@app.route("/cv")
def cv():
    CV_VIEWS.inc()
    return jsonify({
        "name": "Erez Glik",
        "role": "Integration Consultant | Solution Expert | Performance Engineer",
        "cv_file": env("CV_FILE_NAME", "Erez_Glick_Cv.pdf"),
        "s3_bucket": env("S3_BUCKET_NAME"),
    })

def db_connect():
    return psycopg2.connect(
        host=env("DB_HOST"), dbname=env("DB_NAME"), user=env("DB_USERNAME"), password=env("DB_PASSWORD"), port=5432
    )

@app.route("/db/init")
def db_init():
    conn = db_connect()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS cv_events (
            id SERIAL PRIMARY KEY,
            event_type TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT NOW()
        );
    """)
    cur.execute("INSERT INTO cv_events(event_type) VALUES(%s);", ("db_init_called",))
    conn.commit()
    cur.close()
    conn.close()
    return jsonify({"status": "database initialized and write completed"})

@app.route("/db/events")
def db_events():
    conn = db_connect()
    cur = conn.cursor()
    cur.execute("SELECT id, event_type, created_at FROM cv_events ORDER BY id DESC LIMIT 20;")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    events = [{"id": r[0], "event_type": r[1], "created_at": r[2].isoformat()} for r in rows]
    return jsonify({"count": len(events), "events": events})

@app.route("/s3/upload")
def s3_upload():
    bucket = env("S3_BUCKET_NAME")
    if not bucket:
        return jsonify({"status": "skipped", "reason": "S3_BUCKET_NAME missing"}), 400
    key = f"cv-events/{datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%S')}.txt"
    body = f"Erez CV Platform test upload at {datetime.datetime.utcnow().isoformat()}Z"
    client = boto3.client("s3", region_name=env("AWS_REGION", "eu-west-1"))
    client.put_object(Bucket=bucket, Key=key, Body=body.encode("utf-8"), ContentType="text/plain")
    return jsonify({"status": "uploaded", "bucket": bucket, "key": key})

@app.route("/sns/publish")
def sns_publish():
    topic = env("SNS_TOPIC_ARN")
    if not topic:
        return jsonify({"status": "skipped", "reason": "SNS_TOPIC_ARN missing"}), 400
    client = boto3.client("sns", region_name=env("AWS_REGION", "eu-west-1"))
    client.publish(TopicArn=topic, Subject="Erez CV Platform Event", Message="CV platform backend notification triggered.")
    return jsonify({"status": "sns notification sent"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
