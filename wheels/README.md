# wheels

Python wheel files for the custom SGLang build.

- `sglang_kt-*.whl` — fork of sglang (pure Python, committed to repo)
- `sgl_kernel-*.whl` — CUDA kernel ops (~500MB, **not committed**, CI builds and caches it)

## Getting sgl-kernel wheel

```bash
# From GitHub Release
gh release download --repo <owner>/sglang-kt -p 'sgl_kernel-*.whl' --dir wheels/

# Or trigger manual build
gh workflow run build-kernel.yml -f cuda_arch=8.6
```
