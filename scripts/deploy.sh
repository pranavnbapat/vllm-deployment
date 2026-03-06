#!/usr/bin/env bash
set -euo pipefail

DEFAULT_ENV_FILE="/workspace/ops/vllm.env"
LEGACY_ENV_FILE="/workspace/ops/runpod.env"
ENV_FILE="${1:-${DEFAULT_ENV_FILE}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -eq 0 && ! -f "${ENV_FILE}" && -f "${LEGACY_ENV_FILE}" ]]; then
  ENV_FILE="${LEGACY_ENV_FILE}"
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Env file not found: ${ENV_FILE}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

"${SCRIPT_DIR}/bootstrap_gpu_host.sh"
"${SCRIPT_DIR}/generate_supervisor_config.sh" "${ENV_FILE}"
"${SCRIPT_DIR}/supervisor_manage.sh" /workspace/ops/supervisord.conf start
"${SCRIPT_DIR}/supervisor_manage.sh" /workspace/ops/supervisord.conf status

echo "Deployment complete."
echo "Supervisor UI: http://127.0.0.1:${SUPERVISOR_UI_PORT:-9000} (tunnel this port if remote)"
echo "vLLM API: http://0.0.0.0:${VLLM_PORT:-8000}/v1"
echo "Metrics: http://0.0.0.0:${VLLM_PORT:-8000}/metrics"
