#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Deprecated: use scripts/bootstrap_gpu_host.sh"
exec "${SCRIPT_DIR}/bootstrap_gpu_host.sh" "$@"
