#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root (or via sudo)." >&2
  exit 1
fi

PUBLIC_PORT="${1:-9002}"
PROXY_USER="${2:-superadmin}"
PROXY_PASS="${3:-}"
ALLOW_IP="${4:-}"

SUP_CONF="/workspace/ops/supervisord.conf"
HTPASSWD_FILE="/etc/nginx/.htpasswd_supervisor"
NGINX_CONF="/etc/nginx/conf.d/supervisor-public.conf"

if [[ ! -f "${SUP_CONF}" ]]; then
  echo "Missing ${SUP_CONF}. Generate Supervisor config first." >&2
  exit 1
fi

if ! grep -q "^\[inet_http_server\]" "${SUP_CONF}"; then
  echo "Missing [inet_http_server] in ${SUP_CONF}." >&2
  exit 1
fi

SUP_BIND="$(awk '/^\[inet_http_server\]/{flag=1;next}/^\[/{flag=0}flag&&/^port=/{print $0}' "${SUP_CONF}" | head -n1 | cut -d= -f2-)"
if [[ -z "${SUP_BIND}" ]]; then
  echo "Could not read Supervisor inet_http_server port from ${SUP_CONF}." >&2
  exit 1
fi

if [[ "${SUP_BIND}" != 127.0.0.1:* ]]; then
  echo "Unsafe Supervisor bind detected (${SUP_BIND}). Bind it to 127.0.0.1 first." >&2
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1 || ! command -v htpasswd >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y nginx apache2-utils
fi

if [[ -z "${PROXY_PASS}" ]]; then
  PROXY_PASS="$(openssl rand -base64 36 | tr -d '\n')"
fi

htpasswd -bc "${HTPASSWD_FILE}" "${PROXY_USER}" "${PROXY_PASS}" >/dev/null
chmod 640 "${HTPASSWD_FILE}"

ALLOW_BLOCK=""
if [[ -n "${ALLOW_IP}" ]]; then
  ALLOW_BLOCK="    allow ${ALLOW_IP};\n    deny all;"
fi

cat > "${NGINX_CONF}" <<EON
server {
    listen ${PUBLIC_PORT};
    server_name _;

${ALLOW_BLOCK}

    auth_basic "Restricted";
    auth_basic_user_file ${HTPASSWD_FILE};

    location / {
        proxy_pass http://${SUP_BIND};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EON

nginx -t
nginx -s reload >/dev/null 2>&1 || nginx

echo
echo "Public proxy configured."
echo "Supervisor backend: http://${SUP_BIND}"
echo "Public proxy listen: 0.0.0.0:${PUBLIC_PORT}"
echo "Proxy username: ${PROXY_USER}"
echo "Proxy password: ${PROXY_PASS}"
if [[ -n "${ALLOW_IP}" ]]; then
  echo "IP allowlist enabled for: ${ALLOW_IP}"
fi
echo
echo "Next: expose port ${PUBLIC_PORT} in RunPod and open:"
echo "https://<pod-id>-${PUBLIC_PORT}.proxy.runpod.net"
