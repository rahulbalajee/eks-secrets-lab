#!/usr/bin/env bash
set -euo pipefail
kind delete cluster --name secrets-lab
kind delete cluster --name secrets-lab-encrypted 2>/dev/null || true
