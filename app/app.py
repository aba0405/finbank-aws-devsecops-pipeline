"""FinBank Digital - minimal demo service.

Intentionally tiny: the point of this project is the SECURE DELIVERY PIPELINE
around the app, not the app itself. It exposes a health endpoint (used by the
ALB target group and ECS health check) and a root endpoint.
"""
import os
from flask import Flask, jsonify

app = Flask(__name__)

# Read build/version metadata injected at container build time.
# We deliberately source these from the environment so the pipeline can stamp
# the running image with its git SHA -- useful for proving "this exact commit
# is what deployed" in your portfolio writeup.
APP_VERSION = os.environ.get("APP_VERSION", "dev")
GIT_SHA = os.environ.get("GIT_SHA", "local")


@app.route("/")
def index():
    return jsonify(
        service="finbank-digital",
        message="Secure delivery pipeline demo",
        version=APP_VERSION,
        commit=GIT_SHA,
    )


@app.route("/health")
def health():
    # ALB + ECS both hit this. Keep it cheap and dependency-free.
    return jsonify(status="healthy"), 200


if __name__ == "__main__":
    # 0.0.0.0 so the container is reachable from the ECS/ALB network.
    # Port 8080 to avoid needing root for port 80 inside the container.
    app.run(host="0.0.0.0", port=8080)
