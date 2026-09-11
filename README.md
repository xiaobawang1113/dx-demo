# dx-demo（Firefly RK3588）

DEEPX NPU 演示集合。本仓库是在 Firefly RK3588（Ubuntu 22.04 aarch64）上调通后的源码，**不含**模型、视频和 Python 虚拟环境。

显示分辨率请用 **1920×1080**。

## 准备

```bash
cd /home/teamhd/dx-demo
source toolchain.env
./setup_assets.sh          # 下载 workspace/ 下的模型与视频
```

摄像头一般是 `/dev/video1`（`video0` 为 HDMI RX）。`toolchain.env` 里已默认 `DX_CAMERA_IDX=1`。

## 启动

```bash
export DISPLAY=:0
export QT_QPA_PLATFORM=xcb

./scripts/run_launcher.sh          # 桌面启动器
./scripts/run_ocr_web.sh           # OCR Web（API :8080，界面 :7860）
./scripts/run_hands.sh             # 手势（摄像头）
./scripts/run_drone_1.sh           # 目标跟踪（MixFormer）
```

OCR 需设置：

```bash
export PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True
```

默认走 **DEEPX NPU**，不要预加载 CPU PaddleOCR。

## 重建 C++ 演示

```bash
source toolchain.env
cmake --build apps/drone/cpp/build --target drone_mixformer -j4
cmake --build apps/hand-landmark/cpp/build --target hand-landmark-pose -j4
```

改完代码后先关掉旧进程，再从启动器重开。

## 仓库里没有什么

| 路径 | 说明 |
| --- | --- |
| `workspace/` | 模型与视频，用 `setup_assets.sh` 下载 |
| `.cache/`、`venv/`、`.venv/` | 缓存和虚拟环境 |
| `*.dxnn`、`*.mp4` | 模型与视频文件 |

## 目录

| 路径 | 说明 |
| --- | --- |
| `launcher/` | PyQt5 启动器 |
| `scripts/` | 各 demo 启动 / 停止脚本 |
| `apps/drone/` | MixFormer 目标跟踪 |
| `apps/hand-landmark/` | 手势 |
| `apps/paddle-ocr-web/` | PP-OCRv5 Web |
| `apps/yolo26/`、`apps/yolo-multi/` | 检测相关 |
| `apps/depth/`、`apps/automotive/` | 深度 / 自动驾驶 |
