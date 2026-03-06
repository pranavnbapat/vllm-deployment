# vLLM + Supervisor GPU Deployment

This repo turns manual GPU-host setup into a repeatable flow for vLLM serving.
It works on RunPod and other Linux GPU environments with similar privileges.

## What it sets up

- System packages (`curl`, `nano`, `git`, `ffmpeg`, `tesseract-ocr`, `supervisor`, etc.)
- Python venv for vLLM in `/workspace/envs/vllm`
- Supervisor-managed vLLM service
- Optional Supervisor-managed `media_transcriber` service
- Supervisor web UI bound to localhost (`127.0.0.1`) with auth
- vLLM metrics endpoint (`/metrics`) for Prometheus/Grafana

## Files

- `scripts/bootstrap_gpu_host.sh`: base package + vLLM install
- `scripts/generate_supervisor_config.sh`: generates `/workspace/ops/supervisord.conf`
- `scripts/supervisor_manage.sh`: common supervisor operations
- `scripts/metrics_tui.sh`: lightweight live metrics view from `/metrics`
- `scripts/setup_supervisor_public_proxy.sh`: set up Nginx + Basic Auth public proxy for Supervisor UI
- `scripts/deploy.sh`: one-shot bootstrap + configure + start
- `scripts/stop.sh`: one-shot supervisor shutdown for all managed services
- `env/vllm.env.example`: environment template
- `ARCHITECTURE.md`: deployment architecture and security model
- `TROUBLESHOOTING.md`: common errors and fixes from real setup runs

## Quick start on a fresh GPU host

1. Create `services` directory and clone this repo:
   ```bash
   mkdir -p /workspace/services
   cd /workspace/services
   git clone https://github.com/pranavnbapat/vllm-deployment.git
   cd vllm-deployment
   ```
2. Install required system packages first (includes `nano`, `curl`, `supervisor`, etc.):
   ```bash
   sudo bash scripts/bootstrap_gpu_host.sh
   ```
3. Copy env template:
   ```bash
   mkdir -p /workspace/ops
   cp env/vllm.env.example /workspace/ops/vllm.env
   nano /workspace/ops/vllm.env
   ```
4. Set at minimum:
   - `VLLM_MODEL`
   - `SERVED_MODEL_NAME`
   - `VLLM_API_KEY` (long random token)
   - `SUPERVISOR_UI_PASS` (strong password)
5. Generate config and start services:
   ```bash
   bash scripts/generate_supervisor_config.sh /workspace/ops/vllm.env
   bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf start
   bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status
   ```
6. Wait for model startup (can take a few minutes) and verify:
   ```bash
   watch -n 2 "bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status; ss -ltnp | grep 8000 || true"
   ```

7. Readiness check (explicit, with timeout):
   ```bash
   source /workspace/ops/vllm.env
   timeout 1200 bash -c 'until curl -fsS -H "Authorization: Bearer $VLLM_API_KEY" http://127.0.0.1:8000/v1/models >/dev/null; do echo "not ready yet"; sleep 5; done; echo "READY"'
   ```
   - `READY` means API is serving requests.
   - `timeout` after 1200s (20 min) means startup failed or is stuck; check logs.

## Generate vLLM API key

`vllm --api-key` accepts any string format (no required prefix/suffix/algorithm), but use a long random token.

OpenSSL method:
```bash
openssl rand -base64 48 | tr -d '\\n'
```

Python method:
```bash
python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
```

Set it in `/workspace/ops/vllm.env`:
```bash
VLLM_API_KEY=your_generated_token_here
```

## Script order (exact)

### First-time deploy (recommended one command)

```bash
cd /workspace/services/vllm-deployment
sudo bash scripts/deploy.sh /workspace/ops/vllm.env
```

`deploy.sh` runs these in order:

1. `scripts/bootstrap_gpu_host.sh`
   - Installs system dependencies (`supervisor`, `curl`, `nano`, `ffmpeg`, etc.)
   - Creates workspace directories
   - Creates `/workspace/envs/vllm` and installs `vllm`
2. `scripts/generate_supervisor_config.sh /workspace/ops/vllm.env`
   - Reads env values
   - Generates `/workspace/ops/run_vllm.sh`
   - Generates `/workspace/ops/supervisord.conf`
   - Optionally sets up `media_transcriber` if enabled
3. `scripts/supervisor_manage.sh /workspace/ops/supervisord.conf start`
   - Starts `supervisord`
4. `scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status`
   - Prints service status

### Manual equivalent (if you don’t use deploy.sh)

```bash
sudo bash scripts/bootstrap_gpu_host.sh
bash scripts/generate_supervisor_config.sh /workspace/ops/vllm.env
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf start
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status
```

### When you change model/API key/settings later

```bash
nano /workspace/ops/vllm.env
bash scripts/generate_supervisor_config.sh /workspace/ops/vllm.env
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf reload
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf restart vllm_text_8000
```

## Daily operations

Status:
```bash
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status
```

Restart vLLM:
```bash
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf restart vllm_text_8000
```

Apply supervisor config changes:
```bash
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf reload
```

Shutdown all services:
```bash
bash scripts/stop.sh
```

Follow logs:
```bash
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf tail vllm_text_8000
```

Metrics TUI:
```bash
bash scripts/metrics_tui.sh http://127.0.0.1:8000/metrics 2
```

Public Supervisor UI (hardened proxy):
```bash
sudo bash scripts/setup_supervisor_public_proxy.sh 9002 superadmin
```

## Validation

Health/metadata:
```bash
source /workspace/ops/vllm.env
curl -s -H "Authorization: Bearer $VLLM_API_KEY" http://127.0.0.1:8000/v1/models | jq .
```

Metrics:
```bash
curl -s http://127.0.0.1:8000/metrics | grep -E "kv_cache|num_requests"
```

GPU quick check:
```bash
nvidia-smi
```

If `supervisor status` is `RUNNING` but `curl` gets `Connection refused` on `:8000`, check logs:
```bash
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf tail vllm_text_8000
```

Also verify the effective port if you changed `VLLM_PORT`:
```bash
source /workspace/ops/vllm.env
echo "VLLM_PORT=$VLLM_PORT"
ss -ltnp | grep ":${VLLM_PORT}" || true
```

Common cause is unsupported model architecture in your current `vllm`/`transformers` stack. To switch to a known-working model:
```bash
sed -i 's|^VLLM_MODEL=.*|VLLM_MODEL=Qwen/Qwen2.5-7B-Instruct|' /workspace/ops/vllm.env
sed -i 's|^SERVED_MODEL_NAME=.*|SERVED_MODEL_NAME=qwen2.5-7b|' /workspace/ops/vllm.env
sed -i 's|^TRUST_REMOTE_CODE=.*|TRUST_REMOTE_CODE=false|' /workspace/ops/vllm.env
bash scripts/generate_supervisor_config.sh /workspace/ops/vllm.env
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf restart vllm_text_8000
```

## Expected deployment time

On a fresh GPU host, expect about **8 to 25 minutes** in typical cases.

- `apt-get update/install`: ~1 to 5 minutes
- Python + `vllm` install: ~3 to 12 minutes
- First model download from Hugging Face: ~3 to 30+ minutes (largest variable)
- Model load/warmup: ~1 to 5 minutes

If the model is already cached under `/workspace`, restarts are usually **1 to 4 minutes**.
During startup, Supervisor may show `STARTING` and port `8000` may not listen yet; this is normal while weights and KV cache initialize.

## Public Supervisor UI (optional)

Default recommendation is to keep Supervisor UI private on `127.0.0.1:9000`.

If you still want public access, use a protected reverse proxy:

```bash
sudo bash scripts/setup_supervisor_public_proxy.sh 9002 superadmin
```

Arguments:
- arg1: public port (default `9002`)
- arg2: proxy username (default `superadmin`)
- arg3: proxy password (optional; autogenerated if omitted)
- arg4: optional single IP allowlist (for example `1.2.3.4`)

Examples:

```bash
# Auto-generate password
sudo bash scripts/setup_supervisor_public_proxy.sh 9002 superadmin

# Set explicit password
sudo bash scripts/setup_supervisor_public_proxy.sh 9002 superadmin 'VeryStrongPasswordHere'

# Restrict to one public IP
sudo bash scripts/setup_supervisor_public_proxy.sh 9002 superadmin 'VeryStrongPasswordHere' 1.2.3.4
```

Then expose that port in your hosting provider and open:

```text
http(s)://<public-host>:9002
```

You will see two auth layers:
1. Nginx Basic Auth
2. Supervisor UI login

## Troubleshooting

If setup or startup fails, use:

- [TROUBLESHOOTING.md](/home/pranav/PyCharm/Personal/vllm-deployment/TROUBLESHOOTING.md)

## Security notes

- Do not commit `/workspace/ops/vllm.env`.
- Keep Supervisor UI on `127.0.0.1` and do not expose port `9000` publicly.
- If exposing a public dashboard, prefer the Nginx proxy script with strong password and optional IP allowlist.
- Rotate `VLLM_API_KEY` if exposed.
- Exposed ports are often public by default; add your own auth for internet-facing services.
