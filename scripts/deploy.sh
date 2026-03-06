#!/usr/bin/env bash
set -euo pipefail

DEFAULT_ENV_FILE="/workspace/ops/vllm.env"
ENV_FILE="${1:-${DEFAULT_ENV_FILE}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ENV_FILE="${SCRIPT_DIR}/../env/vllm.env.example"

if [[ ! -f "${ENV_FILE}" ]]; then
  mkdir -p "$(dirname "${ENV_FILE}")"
  if [[ -f "${TEMPLATE_ENV_FILE}" ]]; then
    cp "${TEMPLATE_ENV_FILE}" "${ENV_FILE}"
    echo "Created env file from template: ${ENV_FILE}"
    echo "Edit optional values if needed, then rerun this command."
    exit 1
  fi
  echo "Env file not found: ${ENV_FILE}" >&2
  echo "Template not found at: ${TEMPLATE_ENV_FILE}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

if [[ -z "${VLLM_API_KEY:-}" || "${VLLM_API_KEY}" == "replace-with-long-random-token" ]]; then
  GENERATED_VLLM_API_KEY="$(head -c 48 /dev/urandom | base64 | tr -d '\n')"
  if grep -q '^VLLM_API_KEY=' "${ENV_FILE}"; then
    sed -i "s|^VLLM_API_KEY=.*|VLLM_API_KEY=${GENERATED_VLLM_API_KEY}|" "${ENV_FILE}"
  else
    printf '\nVLLM_API_KEY=%s\n' "${GENERATED_VLLM_API_KEY}" >> "${ENV_FILE}"
  fi
  VLLM_API_KEY="${GENERATED_VLLM_API_KEY}"
  export VLLM_API_KEY
  echo "Generated VLLM_API_KEY and updated ${ENV_FILE}:"
  echo "${VLLM_API_KEY}"
fi

if [[ -z "${SUPERVISOR_UI_PASS:-}" || "${SUPERVISOR_UI_PASS}" == "replace-with-strong-password" ]]; then
  GENERATED_SUPERVISOR_UI_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || true)"
  if grep -q '^SUPERVISOR_UI_PASS=' "${ENV_FILE}"; then
    sed -i "s|^SUPERVISOR_UI_PASS=.*|SUPERVISOR_UI_PASS=${GENERATED_SUPERVISOR_UI_PASS}|" "${ENV_FILE}"
  else
    printf '\nSUPERVISOR_UI_PASS=%s\n' "${GENERATED_SUPERVISOR_UI_PASS}" >> "${ENV_FILE}"
  fi
  SUPERVISOR_UI_PASS="${GENERATED_SUPERVISOR_UI_PASS}"
  export SUPERVISOR_UI_PASS
  echo "Generated SUPERVISOR_UI_PASS and updated ${ENV_FILE}:"
  echo "${SUPERVISOR_UI_PASS}"
fi

"${SCRIPT_DIR}/bootstrap_gpu_host.sh"
"${SCRIPT_DIR}/generate_supervisor_config.sh" "${ENV_FILE}"
"${SCRIPT_DIR}/supervisor_manage.sh" /workspace/ops/supervisord.conf start
"${SCRIPT_DIR}/supervisor_manage.sh" /workspace/ops/supervisord.conf status

echo "Deployment complete."
echo "Supervisor UI: http://127.0.0.1:${SUPERVISOR_UI_PORT:-9000} (tunnel this port if remote)"
echo "vLLM API: http://0.0.0.0:${VLLM_PORT:-8000}/v1"
echo "Metrics: http://0.0.0.0:${VLLM_PORT:-8000}/metrics"
