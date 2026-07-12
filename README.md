# sglang-kt

Кастомная сборка [SGLang](https://github.com/sgl-project/sglang) для GPU с Compute Capability 8.x (SM86/SM89).

## Особенности

- **SM86 fallback** — `common_ops` для SM86 загружают SM90-версию с fast-math
- **Flash Attention 3 отключён** — экономит память при сборке
- **Сборка только под SM86** — `TORCH_CUDA_ARCH_LIST=8.6` ускоряет компиляцию
- **Два режима сборки** — из pre-built wheel (быстро) или из исходников (самостоятельная компиляция)

## Быстрый старт

```bash
# Собрать образ (pre-built wheel для sgl-kernel автоматически, если есть в wheels/)
docker build --tag sglang-kt .

# Если нет pre-built sgl-kernel — компиляция с OOM-защитой
docker build --build-arg MAX_JOBS=1 --memory=8g --tag sglang-kt .

# Запустить сервер
docker run --gpus all -p 30000:30000 --rm sglang-kt \
  python3 -m sglang.launch_server --model meta-llama/Llama-3.1-8B-Instruct
```

## Сборка в GitHub Actions

| Workflow | Триггер | Описание |
|---|---|---|
| [CI](.github/workflows/ci.yml) | push/PR в `main` | Сборка sgl-kernel + Docker image, публикация в `ghcr.io` |
| [Release](.github/workflows/release.yml) | тег `v*` | Публикация релиза + Docker image + артефакты |
| [Rebuild sgl-kernel](.github/workflows/build-kernel.yml) | `workflow_dispatch` | Ручная пересборка sgl-kernel под нужную архитектуру |

### Автоматическая загрузка sgl-kernel wheel

CI автоматически собирает `sgl-kernel` из исходников при первом запуске или смене патча.
Собранный wheel кешируется и используется для последующих сборок — Docker образ собирается без компиляции CUDA.

### Переменные сборки (build-arg)

| Аргумент | По умолчанию | Описание |
|---|---|---|
| `MAX_JOBS` | `1` | Параллельных процессов pip |
| `COMPILE_THREADS` | `1` | Потоков компиляции (ninja/cmake) |
| `TORCH_CUDA_ARCH` | `8.6` | CUDA architecture |
| `SGL_KERNEL_ENABLE_FA3` | `OFF` | Flash Attention 3 |
| `PIP_VERBOSE` | `-vvv` | Уровень детализации pip |

## Структура проекта

```
sglang-kt/
├── .github/workflows/
│   ├── ci.yml                # CI-сборка (push/PR)
│   ├── release.yml           # Публикация релизов (тег v*)
│   └── build-kernel.yml      # Ручная пересборка sgl-kernel
├── patches/
│   └── load_utils_sm86.patch # SM86 fallback для common_ops
├── wheels/
│   └── sglang_kt-*.whl       # SGLang fork (pure Python, committed)
├── Dockerfile
├── .dockerignore
├── .gitignore
└── README.md
```

**Примечание:** `sgl_kernel-*.whl` (CUDA kernel ops, ~500MB) **не хранится** в репозитории — CI собирает и кеширует его автоматически.

## Решение проблем

### OOM при сборке

Если сборка sgl-kernel падает с `signal 9` (SIGKILL) — не хватает памяти.

**При сборке локально:**
```bash
docker build --build-arg MAX_JOBS=1 --build-arg COMPILE_THREADS=1 --memory=8g .
```

**В GitHub Actions** — swap-файл 8ГБ создаётся автоматически перед компиляцией (см. `ci.yml`).

### Лог сборки

- Внутри образа: `/root/sgl-kernel-build.log`
- GitHub Actions: лог прикрепляется к артефактам сборки (`sgl-kernel-build-log`)
- Memory trace: `memory-trace.log` (отслеживание потребления RAM каждые 15–30с)

### Загрузить pre-built sgl-kernel для локальной сборки

```bash
# С GitHub Release
gh release download --repo <owner>/sglang-kt -p 'sgl_kernel-*.whl' --dir wheels/

# Или собрать вручную через workflow
gh workflow run build-kernel.yml -f cuda_arch=8.6
```
