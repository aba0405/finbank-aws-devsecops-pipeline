# DELIBERATELY INSECURE -- security-gate demo ONLY. DO NOT merge to main.
#
# This simulates FinBank's real incident: "hardcoded AWS credentials committed
# to GitHub." The values below are AWS's PUBLISHED documentation placeholders
# (AKIAIOSFODNN7EXAMPLE), not live credentials -- but they match the pattern
# secret scanners flag, which is the point of the demo.
#
# A secret-scanning gate should flag this file and block the pipeline.

import boto3

# BAD: hardcoded credentials in source (this is exactly what you must never do)
AWS_ACCESS_KEY_ID = "AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

def make_client():
    # BAD: passing static long-lived keys instead of using an IAM role
    return boto3.client(
        "s3",
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
    )
