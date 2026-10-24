#!/usr/bin/env bash
# Play the role of Terraform: create the infrastructure in the fake AWS and
# publish its outputs to Parameter Store, plus the database secret.
set -euo pipefail
cd "$(dirname "$0")"
source ./env.sh

queue_url=$(aws sqs create-queue --queue-name video-pipeline-prod-transcode-jobs \
  --query QueueUrl --output text)

aws ssm put-parameter --name /video-pipeline/prod/transcode-queue-url \
  --type String --value "$queue_url" --overwrite >/dev/null
aws ssm put-parameter --name /video-pipeline/prod/output-bucket \
  --type String --value video-pipeline-prod-output-7f3a --overwrite >/dev/null

password=$(openssl rand -hex 16)
aws secretsmanager create-secret --name video-pipeline/prod/db \
  --secret-string "{\"username\":\"transcoder\",\"password\":\"$password\"}" >/dev/null

echo "seeded: queue $queue_url, two parameters, one secret"
