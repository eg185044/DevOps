"""Minimal unit tests for the backend Flask app - run in ci-Jenkinsfile's
"Unit Tests" stage. Deliberately only cover routes that need no live
RDS/S3/SNS (a CI agent Pod has none of those) - /db, /s3, /sns are smoke-
tested against the real, deployed app by cd-Jenkinsfile's "Smoke Test"
stage instead, which is where they belong.
"""
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import app as backend_app  # noqa: E402


def client():
    backend_app.app.testing = True
    return backend_app.app.test_client()


def test_health_returns_ok():
    resp = client().get("/health")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["service"] == "backend"
    assert body["status"] == "ok"
    assert "time" in body


def test_cv_returns_expected_fields():
    resp = client().get("/cv")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["name"] == "Erez Glik"
    assert "cv_file" in body


def test_s3_upload_without_bucket_configured_is_skipped_not_crashed():
    os.environ.pop("S3_BUCKET_NAME", None)
    resp = client().get("/s3/upload")
    assert resp.status_code == 400
    assert resp.get_json()["status"] == "skipped"


def test_sns_publish_without_topic_configured_is_skipped_not_crashed():
    os.environ.pop("SNS_TOPIC_ARN", None)
    resp = client().get("/sns/publish")
    assert resp.status_code == 400
    assert resp.get_json()["status"] == "skipped"
