# dx-demo（Firefly RK3588 复现包）

这是在 **Firefly RK3588 / Ubuntu 22.04 aarch64** 上调通后的 DEEPX 演示源码。另一台机器只要 **SDK / 驱动版本与下表完全一致**，按本文走完就能得到与本机相同、可跑且不报错的 demo（启动器、OCR Web、手势、跟踪等）。

仓库里 **没有** 模型、视频、venv 和 `.dxnn`。这些由 `scripts/setup_repro.sh` 按本机已验证的方式拉下来并编译。

显示分辨率请用 **1920×1080**。

## 必须一致的版本

| 组件 | 本机版本 | 说明 |
| --- | --- | --- |
| 板卡 / 系统 | Firefly RK3588，Ubuntu 22.04 aarch64，Python 3.10 | 换 x86 或不同发行版不算复现 |
| DEEPX SDK | **2.3.0** | 先在目标机装好 SDK，本仓库不包含 NPU 运行时 |
| DX-RT | **3.3.0** | `dxrt-cli -s` 第一行 |
| RT driver | **2.4.1** | 驱动不同则 `.dxnn` / `dx-engine` 对不上 |
| PCIe / FW | 2.2.0 / 2.5.6 | 以 `dxrt-cli -s` 为准 |
| `dx-engine` | **3.3.0**（从 `dx_rt` tag `v3.3.0` 编译） | **禁止** `pip install dx-engine==3.4.0`（3.4 需要驱动 ≥2.5.0） |

目标机执行 `dxrt-cli -s`，应看到 `DXRT v3.3.0` 和 driver `2.4.1`，并且 NPU 设备已识别。

## 一键复现

```bash
git clone https://github.com/xiaobawang1113/dx-demo.git
cd dx-demo
source toolchain.env
./scripts/setup_repro.sh
./scripts/verify_repro.sh
```

`setup_repro.sh` 会：

1. 核对 DX-RT / 驱动版本，定位 `libdxrt`（并生成 `.local` 里给 CMake 用的 `dxrtConfig.cmake`）
2. 下载 `workspace/` 模型与视频（`setup_assets.sh`）
3. **解压** 与本机 hold 匹配的 `poppler-utils 22.02.0-2ubuntu0.3` 到缓存（**不 apt**）
4. 拉取 `dx_rt` **v3.3.0**，给 OCR / 启动器编译 `dx-engine==3.3.0`
5. 创建启动器 `.venv`（aarch64 使用 `--system-site-packages`，走系统 PyQt5）
6. 创建 OCR Gradio + FastAPI 两个 venv，下载 server `.dxnn`，写入 `DXRT_TASK_MAX_LOAD=1`
7. 编译启动器里的 C++ demo（含已调通的 drone MixFormer、hand-landmark）

只检查、不安装：脚本 **不会** `apt-get install`。Firefly 镜像上有大量 hold，乱装 `python3-dev` / `poppler-utils` 会把系统拆坏。缺 cmake / g++ / OpenCV / Qt5 时脚本会列出缺什么，请用与本机相同的已装包补齐。

可选覆盖路径：

```bash
export DXRT_INSTALLED_DIR=/usr/local          # 含 lib/libdxrt.so 的前缀
export DX_CAMERA_IDX=1                        # USB 摄像头；本机 video0 是 HDMI RX
export DX_OCR_SERVER_URL=...                  # OCR server.tar.gz 镜像
```

## 启动（与本机相同）

```bash
cd /path/to/dx-demo
source toolchain.env
export DISPLAY=:0 QT_QPA_PLATFORM=xcb
export PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True

./scripts/run_launcher.sh          # 桌面启动器
./scripts/run_ocr_web.sh           # OCR Web（API :8080，界面 :7860）
./scripts/run_hands.sh             # 手势（摄像头）
./scripts/run_drone_1.sh           # MixFormer 跟踪
```

桌面图标：`~/Desktop/dx-demo.desktop` 可指向 `scripts/start_launcher_desktop.sh`（内部会设 `DISPLAY=:0`）。

## 已调通、不要改回去的行为

**OCR Web**

- 默认 **DEEPX NPU**，`run.sh --use-server --lazy-load`
- `PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True`（变量名必须是这个，否则会去探 HuggingFace）
- 检测模型只加载 **640**；不要默认加载 960 / doc_ori / UVDoc（M1 约 1.92GiB）
- `DXRT_TASK_MAX_LOAD=1`（写成 3 会撑爆设备内存）
- **不要**在启动时预加载 CPU PaddleOCR：本板镜像上会 **SIGSEGV**
- PDF：用缓存里的 `pdftoppm`，不要 apt 装 poppler

**手势**

- 启动器走 C++ `apps/hand-landmark/cpp/build/hand-landmark-pose`
- 摄像头画面是镜像时才翻转左右手标签（`use_camera`）

**跟踪（drone MixFormer）**

- 启动器走 C++ `apps/drone/cpp/build/drone_mixformer`
- ImageNet 归一化 + `stabilize_prediction`（低分保留上一框、限制尺度/位移）
- 不要再加“冻框 / 锁尺寸 / lookahead”那套，小鸡目标会跟丢

**进程**

- 不要对包含 `app.py` / `ocr_service.py` / `run.sh` 的命令行做泛匹配 `pkill`（会误杀正在跑的启动脚本）

## 单独重建 C++

```bash
source toolchain.env
./apps/drone/cpp/build.sh
./apps/hand-landmark/cpp/build.sh
# 或全部：
./build.sh --lang cpp --no-ocr-web
```

改完后先关掉旧进程，再从启动器重开。

## 仓库里没有什么

| 路径 | 说明 |
| --- | --- |
| `workspace/` | 模型与视频，由 `setup_assets.sh` 下载 |
| `.cache/`、`.local/`、`venv/`、`.venv/` | 缓存、CMake shim、虚拟环境 |
| `*.dxnn`、`*.mp4`、`*.tar.gz` | 模型与大文件 |

## 目录

| 路径 | 说明 |
| --- | --- |
| `scripts/setup_repro.sh` | 换机一键部署 |
| `scripts/verify_repro.sh` | 部署后自检 |
| `toolchain.env` | 可搬迁的编译/运行环境（不要写死本机 home） |
| `launcher/` | PyQt5 启动器 |
| `apps/drone/` | MixFormer 目标跟踪 |
| `apps/hand-landmark/` | 手势 |
| `apps/paddle-ocr-web/` | PP-OCRv5 Web |
| `apps/yolo26/`、`apps/yolo-multi/` | 检测 |
| `apps/depth/`、`apps/automotive/` | 深度 / 自动驾驶 |
