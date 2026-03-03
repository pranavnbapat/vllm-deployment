# RunPod vLLM Deployment Architecture

## Goals

- Repeatable one-command deployment on a fresh RunPod GPU pod.
- Process management with Supervisor.
- Observability for vLLM and GPU usage.
- Safe-by-default network posture.

## Components

- `vLLM API server` (default port `8000`): OpenAI-compatible API and `/metrics`.
- `supervisord`: manages long-running processes.
- `Supervisor Web UI` (default `127.0.0.1:9000`): process status and logs.
- `metrics_tui.sh`: lightweight terminal dashboard polling `/metrics`.
- `nvidia-smi`/`nvtop`/`gpustat`: GPU utilization and VRAM monitoring.

## Security Model

- Exposed RunPod ports are public endpoints.
- Supervisor UI is bound to localhost by default and should not be exposed directly.
- vLLM uses API key auth (`--api-key`) sourced from env file.
- Secrets are kept out of repository files.

## Network Recommendations

- Expose `8000` for vLLM API (required for external clients).
- Do not expose `9000` (Supervisor UI).
- If remote Supervisor access is needed, tunnel/port-forward to localhost.
- Optional: put an authenticated reverse proxy on a separate port if you need browser access from internet.

## Deployment Flow

1. Install OS and Python dependencies.
2. Create workspace dirs and venv.
3. Install `vllm`.
4. Generate `/workspace/ops/supervisord.conf` and wrappers from env.
5. Start Supervisor and managed services.
6. Validate API, logs, metrics, and GPU usage.

## Execution Order (Commands)

### First-time deploy (recommended)

```bash
cd /workspace/services/vllm-deployment
sudo bash scripts/deploy.sh /workspace/ops/runpod.env
```

### Internal order used by `deploy.sh`

1. `scripts/bootstrap_runpod.sh`
2. `scripts/generate_supervisor_config.sh /workspace/ops/runpod.env`
3. `scripts/supervisor_manage.sh /workspace/ops/supervisord.conf start`
4. `scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status`

### Manual equivalent

```bash
sudo bash scripts/bootstrap_runpod.sh
bash scripts/generate_supervisor_config.sh /workspace/ops/runpod.env
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf start
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status
```

### After env/model/API key changes

```bash
nano /workspace/ops/runpod.env
bash scripts/generate_supervisor_config.sh /workspace/ops/runpod.env
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf reload
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf restart vllm_text_8000
```

## What You Need To Provide

- `VLLM_MODEL` (HF model ID).
- `SERVED_MODEL_NAME` (public model alias in API responses).
- `VLLM_API_KEY` (strong random token).
- Optional tuning values:
  - `GPU_MEMORY_UTILIZATION`
  - `MAX_MODEL_LEN`
  - `MAX_NUM_SEQS`
  - `MAX_NUM_BATCHED_TOKENS`
  - `TRUST_REMOTE_CODE`
  - `EXTRA_VLLM_ARGS`
- Optional Supervisor UI credentials:
  - `SUPERVISOR_UI_USER`
  - `SUPERVISOR_UI_PASS`

## Model Portability

This setup is model-agnostic for single-model serving.

To switch models, update env values and regenerate config:

```bash
nano /workspace/ops/runpod.env
bash scripts/generate_supervisor_config.sh /workspace/ops/runpod.env
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf reload
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf restart vllm_text_8000
```

As long as the model fits your GPU and your vLLM flags are compatible, the same process works.

## Observability

- vLLM metrics endpoint:
  - `http://127.0.0.1:8000/metrics` (inside pod)
  - `https://<podid>-8000.proxy.runpod.net/metrics` (if port exposed)
- Quick metrics TUI:

```bash
bash scripts/metrics_tui.sh http://127.0.0.1:8000/metrics 2
```

- GPU live monitoring:

```bash
watch -n 1 nvidia-smi
```
