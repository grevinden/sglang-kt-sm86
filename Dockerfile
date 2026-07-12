# =============================================================================
# sglang-kt — кастомная сборка SGLang с SM86 fallback и KT-форком
#
# Режимы сборки sgl-kernel:
#   1. Если wheels/sgl_kernel-*.whl есть в контексте → установка без компиляции
#   2. Если нет → компиляция из исходников sglang (OOM-защита: swap + MAX_JOBS=1)
# =============================================================================

# -------------------------------------------------------------------
# Stage: wheels — pre-built .whl из контекста сборки (wheels/)
# -------------------------------------------------------------------
FROM scratch AS wheels
COPY wheels/*.whl /


# -------------------------------------------------------------------
# Stage: builder — подготовка sgl-kernel
#
#   - Если есть pre-built wheel  → быстрая установка (без компиляции)
#   - Если нет                   → компиляция из исходников sglang
#
# Параметры компиляции (только для режима "из исходников"):
#   MAX_JOBS=1              — кол-во параллельных процессов pip
#   COMPILE_THREADS=1       — кол-во потоков компиляции (ninja/cmake)
#   TORCH_CUDA_ARCH=8.6     — архитектура GPU (SM86 = RTX 4090)
#   SGL_KERNEL_ENABLE_FA3=OFF — отключить Flash Attention 3
#   PIP_VERBOSE=-vvv        — уровень детализации pip
# -------------------------------------------------------------------
FROM lmsysorg/sglang:v0.5.15-cu129 AS builder

ARG MAX_JOBS=1
ARG COMPILE_THREADS=1
ARG TORCH_CUDA_ARCH="8.6"
ARG SGL_KERNEL_ENABLE_FA3="OFF"
ARG PIP_VERBOSE="-vvv"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Копируем wheels (проверим, есть ли pre-built sgl_kernel)
COPY wheels/ /tmp/wheels/

# ------------------------------------------------------------------
# Установка sgl-kernel (выбор: pre-built wheel или компиляция)
# ------------------------------------------------------------------
RUN set -o xtrace && \
    echo "" && \
    echo "==============================================" && \
    echo "  BUILDER: system info" && \
    echo "==============================================" && \
    cat /etc/os-release 2>/dev/null || true && \
    nvidia-smi 2>/dev/null || echo "nvidia-smi: not available" && \
    python3 --version && \
    pip --version && \
    torch_cuda=$(python3 -c "import torch; print(torch.version.cuda)" 2>/dev/null) && \
    echo "PyTorch CUDA: ${torch_cuda:-unknown}" && \
    free -h && \
    df -h && \
    nproc && \
    echo "" && \
    echo "==============================================" && \
    if ls /tmp/wheels/sgl_kernel-*.whl 2>/dev/null; then \
        PREBUILT_WHEEL=$(ls /tmp/wheels/sgl_kernel-*.whl | head -1) && \
        echo "  MODE: using pre-built wheel: $(basename ${PREBUILT_WHEEL})" && \
        echo "==============================================" && \
        echo "" && \
        ls -lh "${PREBUILT_WHEEL}" && \
        echo "" && \
        echo "=== Installing pre-built sgl-kernel wheel ===" && \
        pip install ${PIP_VERBOSE} --no-deps "${PREBUILT_WHEEL}" 2>&1 | tee /tmp/sgl-kernel-build.log && \
        echo "" && \
        echo "=== Installed files ===" && \
        find /usr/local/lib/python3.12/dist-packages/sgl_kernel -type f | sort && \
        echo "" && \
        echo "=== sgl-kernel pre-built install SUCCESS ==="; \
    else \
        echo "  MODE: compiling from source" && \
        echo "==============================================" && \
        echo "" && \
        echo "MAX_JOBS=${MAX_JOBS}" && \
        echo "COMPILE_THREADS=${COMPILE_THREADS}" && \
        echo "TORCH_CUDA_ARCH=${TORCH_CUDA_ARCH}" && \
        echo "SGL_KERNEL_ENABLE_FA3=${SGL_KERNEL_ENABLE_FA3}" && \
        echo "" && \
        echo "--- Installing build dependencies ---" && \
        apt-get update -qq && \
        apt-get install -y -qq --no-install-recommends \
            cmake build-essential git time && \
        cmake --version && \
        gcc --version 2>&1 | head -1 && \
        echo "" && \
        echo "--- Cloning sglang repo ---" && \
        GIT_TRACE=1 GIT_CURL_VERBOSE=1 \
        git clone --depth 1 --progress --verbose \
            https://github.com/sgl-project/sglang.git /tmp/sglang && \
        echo "Commit: $(git -C /tmp/sglang log --oneline -1)" && \
        echo "" && \
        echo "--- Builder env ---" && \
        env | grep -E '^(TORCH|MAX_JOBS|SKBUILD|SGL_KERNEL|CUDA|PATH|HOME)' | sort && \
        echo "" && \
        echo "--- sgl-kernel sources ---" && \
        ls -la /tmp/sglang/sgl-kernel/ && \
        echo "" && \
        cd /tmp/sglang/sgl-kernel && \
        TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH}" \
        SKBUILD_CMAKE_ARGS="-DSGL_KERNEL_COMPILE_THREADS=${COMPILE_THREADS};-DSGL_KERNEL_ENABLE_FA3=${SGL_KERNEL_ENABLE_FA3}" \
        MAX_JOBS=${MAX_JOBS} \
        CMAKE_VERBOSE_MAKEFILE=ON \
        CMAKE_BUILD_PARALLEL_LEVEL=${COMPILE_THREADS} \
        VERBOSE=1 \
        pip install \
            ${PIP_VERBOSE} \
            --no-cache-dir \
            --no-build-isolation \
            --progress-bar on \
            . 2>&1 | tee /tmp/sgl-kernel-build.log && \
        echo "" && \
        echo "=== sgl-kernel compile SUCCESS ===" && \
        echo "--- Installed files ---" && \
        find /usr/local/lib/python3.12/dist-packages/sgl_kernel -type f | sort && \
        echo "" && \
        echo "--- Build log size: $(wc -l < /tmp/sgl-kernel-build.log) lines ---"; \
    fi

# Сохраняем список установленных пакетов
RUN pip freeze > /requirements-builder.txt && \
    echo "--- Builder requirements ---" && \
    cat /requirements-builder.txt


# -------------------------------------------------------------------
# Stage: final — целевой образ
# -------------------------------------------------------------------
FROM lmsysorg/sglang:v0.5.15-cu129

# sgl-kernel (собранный/установленный в builder)
COPY --from=builder /usr/local/lib/python3.12/dist-packages/sgl_kernel /usr/local/lib/python3.12/dist-packages/sgl_kernel
COPY --from=builder /usr/local/lib/python3.12/dist-packages/sgl_kernel-*.dist-info /usr/local/lib/python3.12/dist-packages/
COPY --from=builder /tmp/sgl-kernel-build.log /root/sgl-kernel-build.log
COPY --from=builder /requirements-builder.txt /root/

# SM86 fallback патч
COPY patches/load_utils_sm86.patch /tmp/
RUN set -o xtrace && \
    echo "=== Applying SM86 fallback patch ===" && \
    patch -p1 -d /usr/local/lib/python3.12/dist-packages --verbose < /tmp/load_utils_sm86.patch && \
    echo "=== Patch applied ===" && \
    grep -n 'compute_capability' /usr/local/lib/python3.12/dist-packages/sgl_kernel/load_utils.py && \
    rm /tmp/load_utils_sm86.patch

# sglang-kt wheel
RUN --mount=type=cache,target=/root/.cache \
    --mount=type=bind,from=wheels,source=/,target=/wheels \
    set -o xtrace && \
    echo "" && \
    echo "==============================================" && \
    echo "  Installing sglang-kt wheel" && \
    echo "==============================================" && \
    echo "" && \
    echo "--- Available wheels ---" && \
    ls -lh /wheels/ && \
    echo "" && \
    echo "--- Base requirements (before install) ---" && \
    pip freeze > /requirements-base.txt && \
    cat /requirements-base.txt && \
    echo "" && \
    echo "--- Installing sglang-kt ---" && \
    pip install -vvv \
        --find-links=/wheels \
        --no-index \
        --no-deps \
        sglang-kt 2>&1 && \
    echo "" && \
    echo "=== sglang-kt installed ===" && \
    echo "" && \
    echo "--- Frozen requirements (after install) ---" && \
    pip freeze > /requirements-frozen.txt && \
    cat /requirements-frozen.txt && \
    echo "" && \
    echo "--- Sanity checks ---" && \
    python3 -c "import sglang; print(f'sglang OK: {sglang.__version__}')" 2>&1 || \
    echo "WARNING: sglang import failed" && \
    python3 -c "import sgl_kernel; print(f'sgl_kernel OK')" 2>&1 || \
    echo "WARNING: sgl_kernel import failed"

# Точка входа
ENTRYPOINT ["python3", "-m", "sglang"]
CMD []
