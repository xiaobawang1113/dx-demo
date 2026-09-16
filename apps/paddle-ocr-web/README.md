# OCR Web（上游 + 板级 overlay）

与 [deepx-mskang/dx-demo](https://github.com/deepx-mskang/dx-demo) 相同思路：**不要把 DEEPX 上游整仓 vendoring 进本仓库**，只固定 upstream，板级改动放在 `board/overlay/`。

## 目录

| 路径 | 说明 |
| --- | --- |
| `upstream.lock` | 上游仓库 URL / 分支 /（推荐）commit SHA |
| `fetch_upstream.sh` | 把上游 clone 到 `python/PP-OCRv5_*`、`python/PaddleOCR-deepx` |
| `board/overlay/` | 本板适配文件（覆盖 upstream 同名路径） |
| `apply_board_overlay.sh` | 在 fetch 之后打 overlay |
| `python/build.sh` | venv、dx-engine 3.3.0、`.dxnn`（会先 fetch + overlay） |

## 首次 / 换机

```bash
cd apps/paddle-ocr-web
./fetch_upstream.sh
./apply_board_overlay.sh
./python/build.sh --dx_rt /path/to/dx_rt-3.3.0
```

或从仓库根：`./scripts/setup_repro.sh`（内部会走 `python/build.sh`）。

## 固定 upstream commit（推荐）

1. 在 `upstream.lock` 里填 `*_COMMIT=<full sha>`（留空则用 `*_BRANCH=deepx` 最新）。
2. 跑 `./fetch_upstream.sh`，确认 demo 正常。
3. 把 lock 文件提交进 **本仓库**；上游源码仍在 `python/`，由 `.gitignore` 排除。

## 板级 overlay 里有什么

- `ocr_service.py`：poppler 缓存路径、M1 上可选 640/960/doc 模型加载策略
- `run.sh`：POPPLER_PATH、NPU env
- `deepx_env.sh` / `.env.deepx`：`DXRT_TASK_MAX_LOAD=1`（仅 OCR 进程）
- `deepx/engine/paddleocr.py`：未加载 960 时 `det_router` 回退到 640（避免大图 KeyError）
- `app.py`：Gradio 路径 / 重启相关

### 960 检测模型

- 默认 **只加载 640**（M1 ~1.92GiB 装不下 server 全套 + 960）。
- 大图仍走 `det_router`→960 时，overlay 会 **回退 640**，不会崩。
- 需要 960：下载 `det_v5_960.dxnn` 后 `export DX_OCR_LOAD_DET_960=true` 再启 OCR。

### doc_ori / UVDoc

- 默认不加载（`DX_OCR_LOAD_DOC_MODELS=false`）。
- 需要时在模型齐全的前提下 `export DX_OCR_LOAD_DOC_MODELS=true`。

## Git submodule（可选）

本仓库也可用 submodule 代替 `fetch_upstream.sh`（与官方 `.gitmodules` 里 `dx-ocr/` 条目同类）。当前默认 **clone + lock**，避免把 1GB+ 上游误提交进 history。
