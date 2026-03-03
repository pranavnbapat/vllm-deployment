# RunPod vLLM + Supervisor Deployment

This repo turns your manual RunPod setup into a repeatable flow.

## What it sets up

- System packages (`curl`, `nano`, `git`, `ffmpeg`, `tesseract-ocr`, `supervisor`, etc.)
- Python venv for vLLM in `/workspace/envs/vllm`
- Supervisor-managed vLLM service
- Optional Supervisor-managed `media_transcriber` service
- Supervisor web UI bound to localhost (`127.0.0.1`) with auth
- vLLM metrics endpoint (`/metrics`) for Prometheus/Grafana

## Files

- `scripts/bootstrap_runpod.sh`: base package + vLLM install
- `scripts/generate_supervisor_config.sh`: generates `/workspace/ops/supervisord.conf`
- `scripts/supervisor_manage.sh`: common supervisor operations
- `scripts/metrics_tui.sh`: lightweight live metrics view from `/metrics`
- `scripts/setup_supervisor_public_proxy.sh`: set up Nginx + Basic Auth public proxy for Supervisor UI
- `scripts/deploy.sh`: one-shot bootstrap + configure + start
- `env/runpod.env.example`: environment template
- `ARCHITECTURE.md`: deployment architecture and security model
- `TROUBLESHOOTING.md`: common errors and fixes from real setup runs

## Quick start on a fresh pod

1. Create `services` directory and clone this repo:
   ```bash
   mkdir -p /workspace/services
   cd /workspace/services
   git clone https://github.com/pranavnbapat/vllm-deployment.git
   cd vllm-deployment
   ```
2. Install required system packages first (includes `nano`, `curl`, `supervisor`, etc.):
   ```bash
   sudo bash scripts/bootstrap_runpod.sh
   ```
3. Copy env template:
   ```bash
   mkdir -p /workspace/ops
   cp env/runpod.env.example /workspace/ops/runpod.env
   nano /workspace/ops/runpod.env
   ```
4. Set at minimum:
   - `VLLM_MODEL`
   - `SERVED_MODEL_NAME`
   - `VLLM_API_KEY` (long random token)
   - `SUPERVISOR_UI_PASS` (strong password)
   - If `ENABLE_MEDIA_TRANSCRIBER=true`, also set `MEDIA_REPO_URL`.
5. Generate config and start services:
   ```bash
   bash scripts/generate_supervisor_config.sh /workspace/ops/runpod.env
   bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf start
   bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status
   ```
6. Wait for model startup (can take a few minutes) and verify:
   ```bash
   watch -n 2 "bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status; ss -ltnp | grep 8000 || true"
   ```

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

Set it in `/workspace/ops/runpod.env`:
```bash
VLLM_API_KEY=your_generated_token_here
```

## Script order (exact)

### First-time deploy (recommended one command)

```bash
cd /workspace/services/vllm-deployment
sudo bash scripts/deploy.sh /workspace/ops/runpod.env
```

`deploy.sh` runs these in order:

1. `scripts/bootstrap_runpod.sh`
   - Installs system dependencies (`supervisor`, `curl`, `nano`, `ffmpeg`, etc.)
   - Creates workspace directories
   - Creates `/workspace/envs/vllm` and installs `vllm`
2. `scripts/generate_supervisor_config.sh /workspace/ops/runpod.env`
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
sudo bash scripts/bootstrap_runpod.sh
bash scripts/generate_supervisor_config.sh /workspace/ops/runpod.env
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf start
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status
```

### When you change model/API key/settings later

```bash
nano /workspace/ops/runpod.env
bash scripts/generate_supervisor_config.sh /workspace/ops/runpod.env
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
source /workspace/ops/runpod.env
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

## Expected deployment time

On a fresh RunPod pod, expect about **8 to 25 minutes** in typical cases.

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

Then expose that port in RunPod and open:

```text
https://<pod-id>-9002.proxy.runpod.net
```

You will see two auth layers:
1. Nginx Basic Auth
2. Supervisor UI login

## Troubleshooting

If setup or startup fails, use:

- [TROUBLESHOOTING.md](/home/pranav/PyCharm/Personal/vllm-deployment/TROUBLESHOOTING.md)

## Security notes

- Do not commit `/workspace/ops/runpod.env`.
- Keep Supervisor UI on `127.0.0.1` and do not expose port `9000` publicly.
- If exposing a public dashboard, prefer the Nginx proxy script with strong password and optional IP allowlist.
- Rotate `VLLM_API_KEY` if exposed.
- RunPod exposed ports are public by default; add your own auth for internet-facing services.
