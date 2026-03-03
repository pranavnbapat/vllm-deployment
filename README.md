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
- `scripts/deploy.sh`: one-shot bootstrap + configure + start
- `env/runpod.env.example`: environment template
- `ARCHITECTURE.md`: deployment architecture and security model

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
5. Generate config and start services:
   ```bash
   bash scripts/generate_supervisor_config.sh /workspace/ops/runpod.env
   bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf start
   bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status
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

## Validation

Health/metadata:
```bash
curl -s http://127.0.0.1:8000/v1/models | jq .
```

Metrics:
```bash
curl -s http://127.0.0.1:8000/metrics | grep -E "kv_cache|num_requests"
```

GPU quick check:
```bash
nvidia-smi
```

## Security notes

- Do not commit `/workspace/ops/runpod.env`.
- Keep Supervisor UI on `127.0.0.1` and do not expose port `9001` publicly.
- Rotate `VLLM_API_KEY` if exposed.
- RunPod exposed ports are public by default; add your own auth for internet-facing services.
