# workflows

## `ci.yml` — CI

Triggers on push/PR to `main`. Two jobs:
1. `build-sgl-kernel` — compiles sgl-kernel inside `docker run` (with swap + memory limits), caches result
2. `build-docker` — builds final image using cached wheel, pushes to `ghcr.io`

## `release.yml` — Release

Triggers on tag `v*`. Builds sgl-kernel, builds Docker image, creates GitHub Release with artifacts.

## `build-kernel.yml` — Rebuild sgl-kernel

Manual trigger (`workflow_dispatch`). Compiles sgl-kernel for any CUDA arch (7.5, 8.0, 8.6, 8.9, 9.0). Output: wheel artifact.
