import os
import datetime
from flask import Flask, jsonify
import boto3
import psycopg2

app = Flask(__name__)

def env(name, default=""):
    return os.environ.get(name, default)

@app.route("/health")
def health():
    return jsonify({"service": "backend", "status": "ok", "time": datetime.datetime.utcnow().isoformat() + "Z"})

@app.route("/cv")
def cv():
    return jsonify({
        "name": "Erez Glik",
        "role": "Integration Consultant | Solution Expert | Performance Engineer",
        "cv_file": env("CV_FILE_NAME", "Erez_Glick_Cv.pdf"),
        "s3_bucket": env("S3_BUCKET_NAME"),
    })

@app.route("/db/init")
def db_init():
    conn = psycopg2.connect(
        host=env("DB_HOST"), dbname=env("DB_NAME"), user=env("DB_USERNAME"), password=env("DB_PASSWORD"), port=5432
    )
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

@app.route("/notify")
def notify():
    topic = env("SNS_TOPIC_ARN")
    if not topic:
        return jsonify({"status": "skipped", "reason": "SNS_TOPIC_ARN missing"}), 400
    client = boto3.client("sns", region_name=env("AWS_REGION", "eu-west-1"))
    client.publish(TopicArn=topic, Subject="Erez CV Platform Event", Message="CV platform backend notification triggered.")
    return jsonify({"status": "sns notification sent"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
