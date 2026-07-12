# patches

Runtime patches applied to the installed `sgl_kernel` package inside the Docker image.

## `load_utils_sm86.patch`

Patches `sgl_kernel/load_utils.py` to load SM90 fast-math `.so` binaries on SM86/SM89 GPUs (RTX 30xx/40xx).

Applied in the final Dockerfile stage:
```dockerfile
RUN patch -p1 -d /usr/local/lib/python3.12/dist-packages --verbose < /tmp/load_utils_sm86.patch
```

Changing any patch invalidates the CI cache key (`hashFiles('patches/**')`).
