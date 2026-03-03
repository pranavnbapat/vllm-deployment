#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root (or via sudo)." >&2
  exit 1
fi

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  python3 \
  python3-venv \
  python3-pip \
  git \
  curl \
  wget \
  nano \
  jq \
  htop \
  tmux \
  unzip \
  ffmpeg \
  tesseract-ocr \
  supervisor

# Nice-to-have monitoring utilities (best effort)
apt-get install -y nvtop || true
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade gpustat

mkdir -p "${WORKSPACE_DIR}/services" "${WORKSPACE_DIR}/envs" "${WORKSPACE_DIR}/logs" "${WORKSPACE_DIR}/ops"
mkdir -p "${WORKSPACE_DIR}/vllm/text/logs" "${WORKSPACE_DIR}/vllm/text/.cache"

if [[ ! -d "${WORKSPACE_DIR}/envs/vllm" ]]; then
  python3 -m venv "${WORKSPACE_DIR}/envs/vllm"
fi

"${WORKSPACE_DIR}/envs/vllm/bin/python" -m pip install --upgrade pip
"${WORKSPACE_DIR}/envs/vllm/bin/pip" install --upgrade "vllm"

echo "Bootstrap complete."
echo "Next: copy env/runpod.env.example to ${WORKSPACE_DIR}/ops/runpod.env and edit it."
