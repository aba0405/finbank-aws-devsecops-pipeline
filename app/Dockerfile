# ---- Build a small, non-root, production-ish image ----
# Pinned digest-friendly base. Slim keeps the attack surface (and scan noise) down.
FROM python:3.12-slim

# Don't write .pyc files; flush stdout so CloudWatch sees logs immediately.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install deps first so Docker layer caching skips reinstall when only app code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Run as a non-root user. Inspector/most scanners flag root containers -- this
# is the kind of "I fixed a real finding" detail interviewers like.
RUN useradd --create-home --uid 10001 appuser
USER appuser

EXPOSE 8080

# gunicorn, not the Flask dev server, for the running container.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
