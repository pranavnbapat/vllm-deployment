#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-/workspace/ops/runpod.env}"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Env file not found: ${ENV_FILE}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
APP_ROOT="${APP_ROOT:-${PWD}}"
VLLM_HOST="${VLLM_HOST:-0.0.0.0}"
VLLM_PORT="${VLLM_PORT:-8000}"
SUPERVISOR_UI_HOST="${SUPERVISOR_UI_HOST:-127.0.0.1}"
SUPERVISOR_UI_PORT="${SUPERVISOR_UI_PORT:-9001}"
CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
VLLM_MODEL="${VLLM_MODEL:-Qwen/Qwen2.5-7B-Instruct}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-qwen2.5-7b}"
VLLM_DTYPE="${VLLM_DTYPE:-auto}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.90}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-32768}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-4}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-32768}"
TRUST_REMOTE_CODE="${TRUST_REMOTE_CODE:-false}"
EXTRA_VLLM_ARGS="${EXTRA_VLLM_ARGS:-}"
SUPERVISOR_UI_USER="${SUPERVISOR_UI_USER:-admin}"
SUPERVISOR_UI_PASS="${SUPERVISOR_UI_PASS:-change-me}"
ENABLE_MEDIA_TRANSCRIBER="${ENABLE_MEDIA_TRANSCRIBER:-false}"
MEDIA_REPO_URL="${MEDIA_REPO_URL:-}"
MEDIA_REPO_DIR="${MEDIA_REPO_DIR:-/workspace/services/media_transcriber}"
MEDIA_PORT="${MEDIA_PORT:-8005}"
BASIC_USER="${BASIC_USER:-}"
BASIC_PASS="${BASIC_PASS:-}"

if [[ -z "${VLLM_API_KEY:-}" || "${VLLM_API_KEY}" == "replace-with-long-random-token" ]]; then
  echo "Set VLLM_API_KEY in ${ENV_FILE}." >&2
  exit 1
fi

mkdir -p "${WORKSPACE_DIR}/ops" "${WORKSPACE_DIR}/logs" "${WORKSPACE_DIR}/vllm/text/logs" "${WORKSPACE_DIR}/vllm/text/.cache"

cat > "${WORKSPACE_DIR}/ops/run_vllm.sh" <<EOV
#!/usr/bin/env bash
set -euo pipefail
export CUDA_VISIBLE_DEVICES='${CUDA_VISIBLE_DEVICES}'
export HF_HOME='${WORKSPACE_DIR}/vllm/text/.cache/huggingface'
export HF_HUB_CACHE='${WORKSPACE_DIR}/vllm/text/.cache/huggingface/hub'
export TRANSFORMERS_CACHE='${WORKSPACE_DIR}/vllm/text/.cache/huggingface/transformers'
export VLLM_CACHE_DIR='${WORKSPACE_DIR}/vllm/text/.cache/vllm'
export TORCH_HOME='${WORKSPACE_DIR}/vllm/text/.cache/torch'
export PYTORCH_CUDA_ALLOC_CONF='expandable_segments:True'
exec '${WORKSPACE_DIR}/envs/vllm/bin/vllm' serve '${VLLM_MODEL}' \
  --host '${VLLM_HOST}' \
  --port '${VLLM_PORT}' \
  --dtype '${VLLM_DTYPE}' \
  --gpu-memory-utilization '${GPU_MEMORY_UTILIZATION}' \
  --max-model-len '${MAX_MODEL_LEN}' \
  --max-num-seqs '${MAX_NUM_SEQS}' \
  --max-num-batched-tokens '${MAX_NUM_BATCHED_TOKENS}' \
  --served-model-name '${SERVED_MODEL_NAME}' \
  $( [[ "${TRUST_REMOTE_CODE}" == "true" ]] && echo "--trust-remote-code" ) \
  --api-key '${VLLM_API_KEY}' \
  ${EXTRA_VLLM_ARGS}
EOV
chmod 700 "${WORKSPACE_DIR}/ops/run_vllm.sh"

if [[ "${ENABLE_MEDIA_TRANSCRIBER}" == "true" ]]; then
  if [[ -z "${MEDIA_REPO_URL}" ]]; then
    echo "ENABLE_MEDIA_TRANSCRIBER=true but MEDIA_REPO_URL is empty in ${ENV_FILE}." >&2
    exit 1
  fi
  mkdir -p "${WORKSPACE_DIR}/envs"
  if [[ ! -d "${MEDIA_REPO_DIR}" ]]; then
    git clone "${MEDIA_REPO_URL}" "${MEDIA_REPO_DIR}"
  fi
  if [[ ! -d "${WORKSPACE_DIR}/envs/media_transcriber" ]]; then
    python3 -m venv "${WORKSPACE_DIR}/envs/media_transcriber"
  fi
  "${WORKSPACE_DIR}/envs/media_transcriber/bin/python" -m pip install --upgrade pip
  "${WORKSPACE_DIR}/envs/media_transcriber/bin/pip" install -r "${MEDIA_REPO_DIR}/requirements.txt"

  cat > "${WORKSPACE_DIR}/ops/run_media_transcriber.sh" <<EOM
#!/usr/bin/env bash
set -euo pipefail
export BASIC_USER='${BASIC_USER}'
export BASIC_PASS='${BASIC_PASS}'
cd '${MEDIA_REPO_DIR}'
exec '${WORKSPACE_DIR}/envs/media_transcriber/bin/python' -m uvicorn app.main:app --host 0.0.0.0 --port '${MEDIA_PORT}'
EOM
  chmod 700 "${WORKSPACE_DIR}/ops/run_media_transcriber.sh"
fi

cat > "${WORKSPACE_DIR}/ops/supervisord.conf" <<EOS
[supervisord]
user=root
nodaemon=false
logfile=${WORKSPACE_DIR}/logs/supervisord.log
pidfile=${WORKSPACE_DIR}/ops/supervisord.pid

[supervisorctl]
serverurl=unix://${WORKSPACE_DIR}/ops/supervisor.sock

[unix_http_server]
file=${WORKSPACE_DIR}/ops/supervisor.sock
chmod=0700

[inet_http_server]
port=${SUPERVISOR_UI_HOST}:${SUPERVISOR_UI_PORT}
username=${SUPERVISOR_UI_USER}
password=${SUPERVISOR_UI_PASS}

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[program:vllm_text_${VLLM_PORT}]
directory=${WORKSPACE_DIR}
command=/bin/bash -lc ${WORKSPACE_DIR}/ops/run_vllm.sh
autostart=true
autorestart=true
startsecs=20
stopsignal=TERM
stopasgroup=true
killasgroup=true
stdout_logfile=${WORKSPACE_DIR}/vllm/text/logs/vllm_${VLLM_PORT}.log
stderr_logfile=${WORKSPACE_DIR}/vllm/text/logs/vllm_${VLLM_PORT}.err.log
EOS

if [[ "${ENABLE_MEDIA_TRANSCRIBER}" == "true" ]]; then
cat >> "${WORKSPACE_DIR}/ops/supervisord.conf" <<EOS

[program:media_transcriber_${MEDIA_PORT}]
directory=${MEDIA_REPO_DIR}
command=/bin/bash -lc ${WORKSPACE_DIR}/ops/run_media_transcriber.sh
autostart=true
autorestart=true
startsecs=5
stopsignal=TERM
stopasgroup=true
killasgroup=true
stdout_logfile=${WORKSPACE_DIR}/logs/uvicorn_${MEDIA_PORT}.log
stderr_logfile=${WORKSPACE_DIR}/logs/uvicorn_${MEDIA_PORT}.err.log
EOS
fi

echo "Wrote ${WORKSPACE_DIR}/ops/supervisord.conf"
echo "Wrote ${WORKSPACE_DIR}/ops/run_vllm.sh"
[[ "${ENABLE_MEDIA_TRANSCRIBER}" == "true" ]] && echo "Wrote ${WORKSPACE_DIR}/ops/run_media_transcriber.sh"
