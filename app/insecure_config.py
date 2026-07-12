# DELIBERATELY INSECURE -- security-gate demo ONLY. DO NOT merge to main.
#
# Simulates FinBank's real incident: "hardcoded AWS credentials committed to
# GitHub." The key below is FAKE (randomly constructed, not a live credential)
# but uses a realistic AKIA-prefixed format that git-secrets flags.
#
# NOTE: we deliberately do NOT use AWS's documented example key
# (AKIAIOSFODNN7EXAMPLE) because git-secrets allow-lists that specific string.
# Using a non-allowlisted fake key is what makes the gate actually fire.
#
# A secret-scanning gate should flag this file and block the pipeline.

import boto3

# BAD: hardcoded credentials in source (exactly what you must never do)
AWS_ACCESS_KEY_ID = "AKIAZ7XR2NBQK4WT9GDL"
AWS_SECRET_ACCESS_KEY = "8Hy2Kf9pQzRtVwNxLmBcJdEgAhZ3sTuYn6vWqXr"

def make_client():
    # BAD: passing static long-lived keys instead of using an IAM role
    return boto3.client(
        "s3",
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
    )