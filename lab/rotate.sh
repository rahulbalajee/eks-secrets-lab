#!/usr/bin/env bash
# Rotate the database password in the fake Secrets Manager, then watch it
# reach the Kubernetes Secret and the pods.
set -euo pipefail
cd "$(dirname "$0")"
source ./env.sh

password=$(openssl rand -hex 16)
aws secretsmanager put-secret-value --secret-id video-pipeline/prod/db \
  --secret-string "{\"username\":\"transcoder\",\"password\":\"$password\"}" >/dev/null
echo "$(date +%T) rotated the password in Secrets Manager"
[ "${WATCH:-1}" = 1 ] || exit 0
echo "watching the Kubernetes Secret (Ctrl-C to stop)..."
kubectl -n video get secret transcoder-secrets -w \
  -o 'custom-columns=TIME:.metadata.managedFields[-1].time,VERSION:.metadata.resourceVersion'
