# sglang-kt

Custom SGLang build for SM86 GPUs (RTX 30xx/40xx). Entire build is Docker-based — no Python tests, linter, or typecheck in this repo.

## Build

```bash
docker build --tag sglang-kt .
```

If `wheels/sgl_kernel-*.whl` is missing, compilation from source happens (OOM-prone). Add `--build-arg MAX_JOBS=1 --memory=8g` for safety.

## Key files

- `Dockerfile` — three-stage build: `FROM scratch AS wheels` (context), `builder` (compiles/installs sgl-kernel), `final` (patched image)
- `patches/load_utils_sm86.patch` — patches `sgl_kernel/load_utils.py` at runtime to load SM90 fast-math .so on SM86 GPUs
- `wheels/sglang_kt-*.whl` — fork of sglang (pure Python, committed to repo)
- `wheels/sgl_kernel-*.whl` — CUDA kernel ops (~500MB, **not committed**, CI builds and caches it)
- `.github/workflows/ci.yml` — push/PR: builds sgl-kernel in `docker run` → builds Docker → pushes to ghcr.io
- `.github/workflows/build-kernel.yml` — manual rebuild of sgl-kernel for any arch
- `.github/workflows/release.yml` — tag `v*` triggers release + Docker image

## Gotchas

- Base image is pinned: `lmsysorg/sglang:v0.5.15-cu129`
- CI cache key for sgl-kernel uses `hashFiles('patches/**')` — changing any patch invalidates the cache
- `.dockerignore` excludes `*.md` and `*.log` — don't rely on docs being present inside the image
- `sgl_kernel` wheel is installed with `--no-deps` — dependency compatibility is assumed from the base image
- OOM during CUDA compilation is the #1 build failure; CI creates an 8GB swap file inside the container automatically
- CI compiles sgl-kernel via `docker run` (not `docker build`) with memory limits — the Dockerfile itself never compiles
- Entry point is `python3 -m sglang` with empty CMD — must pass arguments (e.g., `launch_server --model ...`)
