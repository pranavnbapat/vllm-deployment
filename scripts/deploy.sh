#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-/workspace/ops/runpod.env}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

"${SCRIPT_DIR}/bootstrap_runpod.sh"
"${SCRIPT_DIR}/generate_supervisor_config.sh" "${ENV_FILE}"
"${SCRIPT_DIR}/supervisor_manage.sh" /workspace/ops/supervisord.conf start
"${SCRIPT_DIR}/supervisor_manage.sh" /workspace/ops/supervisord.conf status

echo "Deployment complete."
echo "Supervisor UI: http://127.0.0.1:${SUPERVISOR_UI_PORT:-9001} (tunnel this port if remote)"
echo "vLLM API: http://0.0.0.0:${VLLM_PORT:-8000}/v1"
echo "Metrics: http://0.0.0.0:${VLLM_PORT:-8000}/metrics"
