#!/usr/bin/env bash
set -euo pipefail

CONF="${1:-/workspace/ops/supervisord.conf}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/supervisor_manage.sh" "${CONF}" stop
