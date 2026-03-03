# Troubleshooting

This page captures real issues seen during RunPod setup and the fixes.

## 1) `nano: command not found`

### Symptom

```bash
bash: nano: command not found
```

### Cause

Base pod does not include editor/tools yet.

### Fix

Run bootstrap first:

```bash
bash scripts/bootstrap_runpod.sh
```

Then edit env:

```bash
nano /workspace/ops/runpod.env
```

## 2) `supervisorctl ... no such file` for `/workspace/ops/supervisor.sock`

### Symptom

```bash
unix:///workspace/ops/supervisor.sock no such file
```

### Cause

`supervisord` is not running yet.

### Fix

```bash
supervisord -c /workspace/ops/supervisord.conf
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status
```

## 3) Service says `RUNNING` but port 8000 not listening

### Symptom

- `status` may briefly show `RUNNING`
- `ss -ltnp | grep 8000` shows nothing
- API/metrics return nothing

### Cause

vLLM process is crash-looping under Supervisor, or still in model initialization.

### Fix

Check vLLM stderr:

```bash
tail -n 200 /workspace/vllm/text/logs/vllm_8000.err.log
```

Also check socket binding and status repeatedly:

```bash
watch -n 2 "bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status; ss -ltnp | grep 8000 || true"
```

## 4) `model type qwen3_5` not recognized / unsupported architecture

### Symptom

Errors like:
- `model type qwen3_5 ... Transformers does not recognize`
- `Model architectures ['Qwen3_5ForConditionalGeneration'] are not supported for now`

### Cause

The selected checkpoint architecture is not supported by current vLLM runtime.

### Fix (recommended)

Use a vLLM-supported model in `runpod.env`:

```bash
VLLM_MODEL=Qwen/Qwen2.5-7B-Instruct
SERVED_MODEL_NAME=qwen2.5-7b
TRUST_REMOTE_CODE=false
```

Apply changes:

```bash
bash scripts/generate_supervisor_config.sh /workspace/ops/runpod.env
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf restart vllm_text_8000
```

## 5) Upgrading `transformers` to 5.x broke vLLM

### Symptom

- pip shows incompatibility: `vllm 0.16.0 requires transformers<5`
- import errors after upgrade

### Cause

Manual upgrade installed incompatible major version.

### Fix

Recreate vLLM venv and reinstall pinned vLLM:

```bash
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf stop
rm -rf /workspace/envs/vllm
python3 -m venv /workspace/envs/vllm
/workspace/envs/vllm/bin/pip install -U pip
/workspace/envs/vllm/bin/pip install "vllm==0.16.0"
bash scripts/generate_supervisor_config.sh /workspace/ops/runpod.env
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf start
```

## 6) `/v1/models` returns empty when server is up

### Cause

You set `--api-key`; endpoint requires auth header.

### Fix

```bash
source /workspace/ops/runpod.env
curl -s -H "Authorization: Bearer $VLLM_API_KEY" http://127.0.0.1:8000/v1/models | jq .
```

## 7) `STARTING` state for several minutes after restart

### Symptom

- `supervisorctl status` shows `STARTING`
- no `ss` listener on `8000` yet

### Cause

Model weights, CUDA graph capture, and KV cache warmup are still in progress.

### Fix

Wait and monitor logs/status. This is expected during cold start:

```bash
watch -n 2 "bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status; ss -ltnp | grep 8000 || true"
tail -f /workspace/vllm/text/logs/vllm_8000.err.log
```

## 8) Old log lines caused confusion (stale crash history)

### Symptom

Error log still shows old `Qwen3_5` crashes even after model change.

### Cause

`vllm_8000.err.log` appends history from previous failed attempts and different PIDs.

### Fix

Inspect latest PIDs in logs and/or clear logs before retry:

```bash
: > /workspace/vllm/text/logs/vllm_8000.log
: > /workspace/vllm/text/logs/vllm_8000.err.log
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf restart vllm_text_8000
```

## 9) Need exact root cause beyond Supervisor logs

### Symptom

Supervisor output is unclear or mixed with older runs.

### Fix

Run vLLM in foreground directly:

```bash
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf stop
bash /workspace/ops/run_vllm.sh
```

If you press `Ctrl+C`, you intentionally stop server (expected shutdown logs).
After confirming healthy startup, run it again with Supervisor:

```bash
supervisord -c /workspace/ops/supervisord.conf
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status
```

## 10) Full recovery sequence used in this setup

When environment/model state got inconsistent, this worked reliably:

```bash
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf stop
rm -rf /workspace/envs/vllm
python3 -m venv /workspace/envs/vllm
/workspace/envs/vllm/bin/pip install -U pip
/workspace/envs/vllm/bin/pip install "vllm==0.16.0"

# Set supported model
sed -i 's|^VLLM_MODEL=.*|VLLM_MODEL=Qwen/Qwen2.5-7B-Instruct|' /workspace/ops/runpod.env
sed -i 's|^SERVED_MODEL_NAME=.*|SERVED_MODEL_NAME=qwen2.5-7b|' /workspace/ops/runpod.env
sed -i 's|^TRUST_REMOTE_CODE=.*|TRUST_REMOTE_CODE=false|' /workspace/ops/runpod.env

bash scripts/generate_supervisor_config.sh /workspace/ops/runpod.env
supervisord -c /workspace/ops/supervisord.conf
```

## 11) API key exposed in terminal/log sharing

### Risk

If the key is pasted in chat/logs/screenshots, treat it as compromised.

### Fix

Generate a new key and update env:

```bash
openssl rand -base64 48 | tr -d '\n'
nano /workspace/ops/runpod.env
bash scripts/generate_supervisor_config.sh /workspace/ops/runpod.env
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf restart vllm_text_8000
```

## 12) Warnings you can usually ignore

- `TRANSFORMERS_CACHE is deprecated` (non-fatal)
- `PYTORCH_CUDA_ALLOC_CONF is deprecated` (non-fatal)
- `unauthenticated requests to HF Hub` (works, but add `HF_TOKEN` for better limits)

## Quick diagnostics block

Run this first when something looks wrong:

```bash
bash scripts/supervisor_manage.sh /workspace/ops/supervisord.conf status
ss -ltnp | grep 8000 || true
tail -n 200 /workspace/logs/supervisord.log
tail -n 200 /workspace/vllm/text/logs/vllm_8000.err.log
```
