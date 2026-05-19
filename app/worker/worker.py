import os
import datetime
from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/health")
def health():
    return jsonify({
        "service": "worker",
        "status": "ok",
        "time": datetime.datetime.utcnow().isoformat() + "Z",
        "bucket": os.environ.get("S3_BUCKET_NAME", "not-configured")
    })

@app.route("/")
def index():
    return jsonify({"service": "worker", "message": "Background worker is running"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("WORKER_PORT", "5002")))
