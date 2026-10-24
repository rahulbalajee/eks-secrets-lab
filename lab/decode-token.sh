#!/usr/bin/env bash
# Ask the API server for a service account token, the same kind the kubelet
# mounts into pods, and print its claims. This is what IRSA hands to STS.
set -euo pipefail
namespace=${1:-video}
service_account=${2:-transcoder}
audience=${3:-sts.amazonaws.com}
kubectl -n "$namespace" create token "$service_account" --audience "$audience" --duration 1h |
  python3 -c '
import base64, json, sys
payload = sys.stdin.read().strip().split(".")[1]
print(json.dumps(json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4))), indent=2))
'
