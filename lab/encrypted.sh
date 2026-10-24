#!/usr/bin/env bash
# Create the encrypted cluster, store one Secret, and read etcd again.
set -euo pipefail
cd "$(dirname "$0")"
dir=$(mktemp -d)
cat > "$dir/config.yaml" <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources: ["secrets"]
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: $(head -c 32 /dev/urandom | base64)
      - identity: {}
EOF
sed "s|ENCRYPTION_DIR|$dir|" kind-encrypted.yaml | kind create cluster --config -
kubectl create namespace video
kubectl -n video create secret generic transcoder-secrets --from-literal=DB_PASSWORD=correct-horse-battery-staple
CLUSTER=secrets-lab-encrypted ./etcd.sh transcoder-secrets video
