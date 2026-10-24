#!/usr/bin/env bash
# Create the lab: kind, a fake AWS, ESO, Reloader, the transcoder.
set -euo pipefail
cd "$(dirname "$0")"
source ./env.sh

kind create cluster --config kind.yaml

sed "s/MOTO_VERSION/${MOTO_VERSION:-5.2.4}/" moto.yaml | kubectl apply -f -
kubectl -n fake-aws rollout status deploy/moto --timeout=180s

helm repo add external-secrets https://charts.external-secrets.io >/dev/null
helm repo add stakater https://stakater.github.io/stakater-charts >/dev/null
helm repo update >/dev/null
helm install external-secrets external-secrets/external-secrets \
  --version "$ESO_CHART_VERSION" -n external-secrets --create-namespace \
  -f eso-values.yaml --wait
helm install reloader stakater/reloader \
  --version "$RELOADER_CHART_VERSION" -n reloader --create-namespace --wait

./seed.sh

docker build -t transcoder:dev ../app
kind load docker-image transcoder:dev --name "$CLUSTER"

kubectl apply -k ../k8s/overlays/lab
kubectl -n video wait externalsecret --all --for=condition=Ready --timeout=120s
kubectl -n video rollout status deploy/transcoder --timeout=120s
kubectl -n video get externalsecret,secret,pods
