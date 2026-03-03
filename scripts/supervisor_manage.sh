#!/usr/bin/env bash
set -euo pipefail

CONF="${1:-/workspace/ops/supervisord.conf}"
ACTION="${2:-status}"
SERVICE="${3:-}"

case "${ACTION}" in
  start)
    supervisord -c "${CONF}"
    ;;
  stop)
    supervisorctl -c "${CONF}" shutdown
    ;;
  restart)
    if [[ -z "${SERVICE}" ]]; then
      echo "Usage: $0 <conf> restart <service>" >&2
      exit 1
    fi
    supervisorctl -c "${CONF}" restart "${SERVICE}"
    ;;
  status)
    supervisorctl -c "${CONF}" status
    ;;
  reload)
    supervisorctl -c "${CONF}" reread
    supervisorctl -c "${CONF}" update
    ;;
  tail)
    if [[ -z "${SERVICE}" ]]; then
      echo "Usage: $0 <conf> tail <service>" >&2
      exit 1
    fi
    supervisorctl -c "${CONF}" tail -f "${SERVICE}"
    ;;
  *)
    echo "Usage: $0 <conf> {start|stop|status|reload|restart <service>|tail <service>}" >&2
    exit 1
    ;;
esac
