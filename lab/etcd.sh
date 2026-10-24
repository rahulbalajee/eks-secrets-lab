#!/usr/bin/env bash
# Read a Secret straight out of etcd, the way someone with a disk or a
# backup could. On a cluster without encryption at rest, the value is
# right there in the bytes.
set -euo pipefail
secret=${1:-transcoder-secrets}
namespace=${2:-video}
cluster=${CLUSTER:-secrets-lab}
kubectl --context "kind-${cluster}" -n kube-system exec "etcd-${cluster}-control-plane" -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get "/registry/secrets/${namespace}/${secret}" --print-value-only | strings
