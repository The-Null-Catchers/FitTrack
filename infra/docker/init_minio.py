"""Initialize the local S3 bucket without the withdrawn MinIO client image."""
import json
import os
import time

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError, EndpointConnectionError

bucket = os.getenv("S3_BUCKET", "fittrack")
client = boto3.client(
    "s3",
    endpoint_url="http://minio:9000",
    aws_access_key_id=os.getenv("S3_ACCESS_KEY", "fittrack"),
    aws_secret_access_key=os.getenv("S3_SECRET_KEY", "fittrack-dev-secret"),
    region_name="us-east-1",
    config=Config(s3={"addressing_style": "path"}, connect_timeout=3, read_timeout=3),
)

for attempt in range(60):
    try:
        client.list_buckets()
        break
    except (BotoCoreError, ClientError, EndpointConnectionError):
        if attempt == 59:
            raise
        time.sleep(2)

try:
    client.create_bucket(Bucket=bucket)
except ClientError as exc:
    if exc.response.get("Error", {}).get("Code") not in (
        "BucketAlreadyOwnedByYou", "BucketAlreadyExists"
    ):
        raise

# Match the previous local bootstrap: anonymous reads for the two public asset prefixes.
policy = {
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": "*",
        "Action": ["s3:GetObject"],
        "Resource": [
            f"arn:aws:s3:::{bucket}/exercise-media/*",
            f"arn:aws:s3:::{bucket}/avatars/*",
        ],
    }],
}
client.put_bucket_policy(Bucket=bucket, Policy=json.dumps(policy))
print("Bucket ready.")
