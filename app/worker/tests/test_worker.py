"""Minimal unit tests for the worker Flask app - run in ci-Jenkinsfile's
"Unit Tests" stage.
"""
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import worker as worker_app  # noqa: E402


def client():
    worker_app.app.testing = True
    return worker_app.app.test_client()


def test_health_returns_ok():
    resp = client().get("/health")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["service"] == "worker"
    assert body["status"] == "ok"


def test_index_reports_running():
    resp = client().get("/")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["service"] == "worker"
    assert "message" in body


def test_metrics_endpoint_exposes_prometheus_format():
    c = client()
    c.get("/")
    resp = c.get("/metrics")
    assert resp.status_code == 200
    body = resp.get_data(as_text=True)
    assert "worker_http_requests_total" in body
    assert "worker_app_info" in body
