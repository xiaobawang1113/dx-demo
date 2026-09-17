# dx-demo

DEEPX NPU 演示集合（启动器、OCR Web、手势、跟踪等）。面向 **SDK 2.3.x Compatible Mode**：客户 RK3588 各厂商板卡、日常 Demo 部署，**不锁死**某一镜像上的 DX-RT / 驱动小版本。

与 [deepx-mskang/dx-demo](https://github.com/deepx-mskang/dx-demo) 同思路：上游 OCR 用 `fetch_upstream.sh` + `board/overlay`，不把整仓上游提交进本 repo。

仓库不含 `workspace/` 模型视频、venv、`.dxnn`（本地生成）。

## Compatible Mode 检查什么

| 项 | 说明 |
| --- | --- |
| DXRT compatible | `dxrt-cli -s` 可识别 **DXRT 3.x**（SDK 2.3.x 产品线） |
| Driver compatible | 驱动信息可读（NPU 未枚举时 WARN，不硬拦部署） |
| libdxrt 存在 | `lib/libdxrt.so`，可用 `DXRT_INSTALLED_DIR` 指定 |
| NPU 存在 | 无 `Device not found` 等（现场无卡可先编译） |
| dx-engine 可 import | `import dx_engine.capi._pydxrt` 成功，且尽量与 libdxrt 同代 |
| 模型可 load | 至少 OCR `det_v5_640.dxnn` 等在盘（或 WARN） |

**不强制** Ubuntu 版本、板卡品牌、RT driver `2.4.1`、dx-engine `3.3.0` 与某台 Firefly 完全一致。版本错位时 `verify_compatible.sh` 会 **WARN**，现场以 NPU 推理为准。

## 一键部署

```bash
git clone https://github.com/xiaobawang1113/dx-demo.git
cd dx-demo
source toolchain.env
./scripts/setup_demo.sh
./scripts/verify_compatible.sh
```

旧脚本名仍可用：`setup_repro.sh` → `setup_demo.sh`，`verify_repro.sh` → `verify_compatible.sh`。

`setup_demo.sh` 会：检查 SDK、下 `workspace/`、按 **当前 `dxrt-cli` 报告的 DXRT 版本** 拉对应 `dx_rt` tag 编译 dx-engine（或用已有 wheel）、OCR upstream + overlay、编译 C++ demo。

```bash
./scripts/setup_demo.sh --skip-cpp    # 只 Python/OCR
./scripts/setup_demo.sh --skip-ocr    # 不要 OCR 环境
```

## 启动

```bash
source toolchain.env
export DISPLAY="${DISPLAY:-:0}" QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
export PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True

./scripts/run_launcher.sh
./scripts/run_ocr_web.sh
./scripts/run_hands.sh
./scripts/run_drone_1.sh
```

`toolchain.env` **不会**把 `DXRT_TASK_MAX_LOAD=1` 套到启动器里其它 demo（避免 FPS 降到约 1/3）。OCR 仅在 `deepx_env.sh` 里设 NPU 缓冲。

摄像头：`source toolchain.env` 后自动选 profile + UVC 设备（见 [profile/README.md](profile/README.md)）。覆盖：`DX_CAMERA_IDX=auto|N`、`DX_CAMERA_BACKEND`、`DX_CAMERA_FOURCC`；调试：`./scripts/dx_camera_info.sh`。

## 板级 OCR 说明

见 [apps/paddle-ocr-web/README.md](apps/paddle-ocr-web/README.md)：`upstream.lock` 可 **选填** commit；M1 小显存默认 det 640 + `TASK_MAX_LOAD=1`，960/doc 模型用环境变量按需打开。

## 目录

| 路径 | 说明 |
| --- | --- |
| `scripts/setup_demo.sh` | Compatible Mode 部署 |
| `scripts/verify_compatible.sh` | 兼容检查 |
| `scripts/lib/dxrt_compat.sh` | 共用 DX-RT 探测 |
| `toolchain.env` | 编译/运行环境 |
| `apps/paddle-ocr-web/` | OCR upstream + overlay |
| `launcher/` | PyQt5 启动器 |
