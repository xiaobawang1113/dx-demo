# dx-demo

在 Firefly RK3588 上调通后的 DEEPX 演示源码。另一台机器 **只要 DEEPX SDK / DX-RT / 驱动版本与下表一致**，按本文部署就能跑同一套已调试好的 demo（启动器、OCR Web、手势、跟踪等）。

**Ubuntu / 发行版 / 板卡型号不必和开发板相同。** 系统相关的差异（摄像头编号、poppler、PyQt5、apt hold）脚本会按目标机自适应，或用环境变量覆盖。

仓库里 **没有** 模型、视频、venv 和 `.dxnn`。由 `scripts/setup_repro.sh` 在目标机生成。

## 必须一致的版本（SDK，不是操作系统）

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| DEEPX SDK | **2.3.0** | 先在目标机装好 SDK，本仓库不含 NPU 运行时 |
| DX-RT | **3.3.0** | `dxrt-cli -s` |
| RT driver | **2.4.1** | 驱动不同则 `.dxnn` / `dx-engine` 对不上 |
| `dx-engine` | **3.3.0**（从 `dx_rt` tag `v3.3.0` 编译） | **禁止** `pip install dx-engine==3.4.0`（3.4 需要驱动 ≥2.5.0） |

目标机执行 `dxrt-cli -s`，应看到 `DXRT v3.3.0` 和 driver `2.4.1`，并且 NPU 已识别。

本机开发环境仅供参考（**不是复现前提**）：Firefly RK3588、Ubuntu 22.04 aarch64、Python 3.10。x86 或其他发行版只要 SDK 对上，同样走 `setup_repro.sh`。

## 一键部署

```bash
git clone https://github.com/xiaobawang1113/dx-demo.git
cd dx-demo
source toolchain.env
./scripts/setup_repro.sh
./scripts/verify_repro.sh
```

`setup_repro.sh` 会：

1. 核对 DX-RT / 驱动，定位 `libdxrt`（生成 `.local` 里给 CMake 用的 `dxrtConfig.cmake`）
2. 下载 `workspace/` 模型与视频
3. PDF：Ubuntu 22.04 aarch64 解压缓存版 poppler；**其他系统用该机自带的 `pdftoppm`**
4. 拉取 `dx_rt` **v3.3.0**，编译 `dx-engine==3.3.0`
5. 创建启动器 `.venv`（能用系统 PyQt5 就用；否则 pip）
6. 创建 OCR 两个 venv，下载 server `.dxnn`，写入 `DXRT_TASK_MAX_LOAD=1`
7. 编译 C++ demo（含已调通的 drone MixFormer、hand-landmark）

脚本 **不会** 擅自 `apt-get install`。缺 cmake / g++ / OpenCV / Qt5 时会列出缺项，由目标机自己装。只有 Firefly 这类带大量 apt hold 的镜像才不要拆 hold。

可选覆盖：

```bash
export DXRT_INSTALLED_DIR=/usr/local   # 含 lib/libdxrt.so 的前缀
export DX_CAMERA_IDX=0                 # 摄像头编号；不对就改
export DISPLAY=:0                      # 桌面 display 不对就改
export DX_OCR_SERVER_URL=...           # OCR server.tar.gz 镜像
```

摄像头：检测到 RK3588/Firefly 时默认 `video1`（`video0` 常是 HDMI RX），其他机器默认 `video0`。

## 启动

```bash
cd /path/to/dx-demo
source toolchain.env
export DISPLAY="${DISPLAY:-:0}" QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
export PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True

./scripts/run_launcher.sh          # 桌面启动器
./scripts/run_ocr_web.sh           # OCR Web（API :8080，界面 :7860）
./scripts/run_hands.sh             # 手势（摄像头）
./scripts/run_drone_1.sh           # MixFormer 跟踪
```

桌面图标可指向 `scripts/start_launcher_desktop.sh`。

## 已调通、换机也不要改回去的行为

这些跟 **SDK / NPU** 有关，跟 Ubuntu 版本无关：

**OCR Web**

- 默认 **DEEPX NPU**，`run.sh --use-server --lazy-load`
- `PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True`（名字必须是这个）
- 检测只加载 **640**；不要默认加载 960 / doc_ori / UVDoc（M1 约 1.92GiB）
- `DXRT_TASK_MAX_LOAD=1`（写成 3 会撑爆设备内存）
- 不要预加载 CPU PaddleOCR（部分镜像上会 SIGSEGV；demo 一律走 NPU）

**手势**

- 启动器走 C++ `hand-landmark-pose`
- 摄像头画面是镜像时才翻转左右手标签

**跟踪（drone MixFormer）**

- 启动器走 C++ `drone_mixformer`
- ImageNet 归一化 + `stabilize_prediction`
- 不要再加冻框 / 锁尺寸 / lookahead，小鸡目标会跟丢

**进程**

- 不要对包含 `app.py` / `ocr_service.py` / `run.sh` 的命令行做泛匹配 `pkill`

## 单独重建 C++

```bash
source toolchain.env
./apps/drone/cpp/build.sh
./apps/hand-landmark/cpp/build.sh
# 或全部：
./build.sh --lang cpp --no-ocr-web
```

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
| `toolchain.env` | 可搬迁的编译/运行环境 |
| `launcher/` | PyQt5 启动器 |
| `apps/drone/` | MixFormer 目标跟踪 |
| `apps/hand-landmark/` | 手势 |
| `apps/paddle-ocr-web/` | PP-OCRv5 Web |
| `apps/yolo26/`、`apps/yolo-multi/` | 检测 |
| `apps/depth/`、`apps/automotive/` | 深度 / 自动驾驶 |
