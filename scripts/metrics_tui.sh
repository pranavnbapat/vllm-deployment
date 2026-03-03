#!/usr/bin/env bash
set -euo pipefail

METRICS_URL="${1:-http://127.0.0.1:8000/metrics}"
INTERVAL="${2:-2}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required." >&2
  exit 1
fi

extract_metric() {
  local name="$1"
  local content="$2"
  echo "${content}" | awk -v n="${name}" '
    $1 ~ "^" n "(" "\\{" ".*" "\\})?$" {
      val=$NF
      if (val ~ /^-?[0-9]+(\.[0-9]+)?([eE]-?[0-9]+)?$/) {
        print val
        exit
      }
    }
  '
}

format_percent() {
  local v="$1"
  if [[ -z "${v}" ]]; then
    echo "n/a"
    return
  fi
  awk -v x="${v}" 'BEGIN { printf "%.2f%%", x * 100 }'
}

while true; do
  clear
  now="$(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "vLLM Metrics TUI"
  echo "Time: ${now}"
  echo "Endpoint: ${METRICS_URL}"
  echo

  if ! body="$(curl -fsS --max-time 3 "${METRICS_URL}")"; then
    echo "Unable to fetch metrics. Retrying in ${INTERVAL}s..."
    sleep "${INTERVAL}"
    continue
  fi

  kv_usage="$(extract_metric 'vllm:kv_cache_usage_perc' "${body}")"
  req_running="$(extract_metric 'vllm:num_requests_running' "${body}")"
  req_waiting="$(extract_metric 'vllm:num_requests_waiting' "${body}")"
  prompt_tps="$(extract_metric 'vllm:avg_prompt_throughput_toks_per_s' "${body}")"
  gen_tps="$(extract_metric 'vllm:avg_generation_throughput_toks_per_s' "${body}")"

  printf '%-38s %s\n' 'KV cache usage:' "$(format_percent "${kv_usage}")"
  printf '%-38s %s\n' 'Requests running:' "${req_running:-n/a}"
  printf '%-38s %s\n' 'Requests waiting:' "${req_waiting:-n/a}"
  printf '%-38s %s\n' 'Avg prompt throughput (tok/s):' "${prompt_tps:-n/a}"
  printf '%-38s %s\n' 'Avg generation throughput (tok/s):' "${gen_tps:-n/a}"
  echo
  echo "Press Ctrl+C to exit."

  sleep "${INTERVAL}"
done
