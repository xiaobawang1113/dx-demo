#!/usr/bin/env bash
# Reproduce this Firefly RK3588 + DX-RT 3.3.0 board setup on another
# machine that already has the same DEEPX SDK / driver installed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/toolchain.env"

EXPECTED_DXRT="3.3.0"
EXPECTED_DRIVER="2.4.1"
OCR_PY="${ROOT}/apps/paddle-ocr-web/python"
FASTAPI="${OCR_PY}/PaddleOCR-deepx/deploy/fastapi"
CACHE="${OCR_PY}/.cache"
DX_RT_SRC="${CACHE}/dx_rt-3.3.0"
POPPLER_VER="22.02.0-2ubuntu0.3"
POPPLER_DIR="${CACHE}/poppler-utils-${POPPLER_VER}"
SERVER_TAR_URL="${DX_OCR_SERVER_URL:-https://sdk.deepx.ai/res/assets/dx_baidu_PPOCR/server.tar.gz}"
DX_RT_TGZ_URL="https://github.com/DEEPX-AI/dx_rt/archive/refs/tags/v3.3.0.tar.gz"

die() { echo "ERROR: $*" >&2; exit 1; }
ok() { echo "OK  $*"; }
step() { echo; echo "======== $* ========"; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1 （请在目标机用包管理器装好依赖。系统版本不必一致；Firefly 镜像若有 apt hold，不要拆 hold）"
}

check_sdk() {
    step "检查 DX-RT / 驱动（必须与本机一致）"
    need_cmd dxrt-cli
    local info
    info="$(dxrt-cli -s 2>&1 || true)"
    echo "${info}"
    echo "${info}" | grep -qE "DXRT v${EXPECTED_DXRT}|DX-RT[[:space:]]*${EXPECTED_DXRT}" \
        || die "DX-RT 不是 ${EXPECTED_DXRT}。版本不一致时不要继续，先装同一套 SDK。"
    if ! echo "${info}" | grep -q "${EXPECTED_DRIVER}"; then
        echo "WARN: 未看到 RT driver ${EXPECTED_DRIVER}。驱动不同会导致 dx-engine / .dxnn 对不上。"
    fi
    if echo "${info}" | grep -qi 'Device not found'; then
        echo "WARN: NPU 设备未找到。demo 需要 M1 卡；先确认 PCIe 识别后再跑推理。"
    fi
    [ -n "${DXRT_INSTALLED_DIR:-}" ] || die "找不到 libdxrt（设 DXRT_INSTALLED_DIR 指向含 lib/libdxrt.so 的前缀）"
    [ -e "${DXRT_INSTALLED_DIR}/lib/libdxrt.so" ] || [ -e /usr/local/lib/libdxrt.so ] \
        || die "DXRT_INSTALLED_DIR=${DXRT_INSTALLED_DIR} 下没有 libdxrt"
    ok "DXRT_INSTALLED_DIR=${DXRT_INSTALLED_DIR}"
}

check_host_tools() {
    step "检查编译工具（只检查，不 apt install）"
    local missing=()
    for c in gcc g++ cmake make pkg-config python3 curl tar; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    pkg-config --exists opencv4 2>/dev/null || pkg-config --exists opencv 2>/dev/null \
        || missing+=("libopencv-dev")
    pkg-config --exists Qt5Widgets 2>/dev/null || missing+=("qtbase5-dev")
    if [ "${#missing[@]}" -gt 0 ]; then
        die "缺少: ${missing[*]}。请在目标机自行安装（系统版本不必和开发板一致）。若该机是带 apt hold 的 Firefly 镜像，不要拆 hold。"
    fi
    ok "gcc/cmake/OpenCV/Qt5 可用"
}

setup_assets() {
    step "下载 workspace 模型与视频"
    bash "${ROOT}/setup_assets.sh"
    [ -d "${ROOT}/workspace/models" ] && [ -d "${ROOT}/workspace/videos" ] \
        || die "setup_assets.sh 之后仍没有 workspace/models 或 videos"
    ok "workspace 就绪"
}

setup_poppler() {
    step "准备 pdftoppm（系统版本不必一致）"
    mkdir -p "${CACHE}"
    if [ -x "${POPPLER_DIR}/usr/bin/pdftoppm" ]; then
        ok "缓存 poppler 已存在"
        return
    fi
    local os_id="" os_ver=""
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        os_id="$(. /etc/os-release && echo "${ID:-}")"
        os_ver="$(. /etc/os-release && echo "${VERSION_ID:-}")"
    fi
    # Only this combo matches the Firefly held libpoppler118; other OS uses system pdftoppm.
    if [ "$(uname -m)" = "aarch64" ] && [ "${os_id}" = "ubuntu" ] && [ "${os_ver}" = "22.04" ]; then
        local deb="${CACHE}/poppler-utils_${POPPLER_VER}_arm64.deb"
        local url="http://ports.ubuntu.com/ubuntu-ports/pool/main/p/poppler/poppler-utils_${POPPLER_VER}_arm64.deb"
        if [ ! -f "${deb}" ]; then
            curl -fL --retry 5 --retry-delay 2 -o "${deb}" "${url}" \
                || die "下载 poppler deb 失败: ${url}"
        fi
        mkdir -p "${POPPLER_DIR}"
        dpkg-deb -x "${deb}" "${POPPLER_DIR}"
        [ -x "${POPPLER_DIR}/usr/bin/pdftoppm" ] || die "poppler 解压后没有 pdftoppm"
        ok "POPPLER_PATH=${POPPLER_DIR}/usr/bin（Ubuntu 22.04 aarch64 缓存解压，不走 apt）"
        return
    fi
    if command -v pdftoppm >/dev/null 2>&1; then
        ok "使用系统 pdftoppm: $(command -v pdftoppm)"
        return
    fi
    echo "WARN: 没有 pdftoppm。图片 OCR 仍可用；PDF 需要目标机自己安装 poppler-utils（版本跟该机系统走）。"
}

setup_dx_rt_src() {
    step "准备 dx_rt v3.3.0 源码（给 dx-engine 3.3.0 用，禁止 PyPI 3.4.0）"
    if [ -f "${DX_RT_SRC}/python_package/pyproject.toml" ] || [ -f "${DX_RT_SRC}/python_package/setup.py" ]; then
        ok "已有 ${DX_RT_SRC}/python_package"
        return
    fi
    mkdir -p "${CACHE}"
    local tgz="${CACHE}/dx_rt-3.3.0.tar.gz"
    if [ ! -f "${tgz}" ]; then
        curl -fL --retry 5 --retry-delay 2 -o "${tgz}" "${DX_RT_TGZ_URL}" \
            || die "下载 dx_rt v3.3.0 失败"
    fi
    rm -rf "${CACHE}/dx_rt-3.3.0-extract"
    mkdir -p "${CACHE}/dx_rt-3.3.0-extract"
    tar -xzf "${tgz}" -C "${CACHE}/dx_rt-3.3.0-extract"
    local top
    top="$(find "${CACHE}/dx_rt-3.3.0-extract" -maxdepth 1 -type d -name 'dx_rt-*' | head -1)"
    [ -n "${top}" ] || die "tarball 里没有 dx_rt 目录"
    rm -rf "${DX_RT_SRC}"
    mv "${top}" "${DX_RT_SRC}"
    ok "dx_rt v3.3.0 -> ${DX_RT_SRC}"
}

setup_launcher_venv() {
    step "启动器 Python 环境"
    bash "${ROOT}/setup_env.sh"
    [ -x "${ROOT}/.venv/bin/python" ] || die ".venv 未创建"
    ok "launcher .venv"
}

write_ocr_deepx_env() {
    cat > "${FASTAPI}/deepx_env.sh" <<'EOF'
#!/bin/bash
# Conservative NPU buffers: M1 has 1.92GiB. Loading every PP-OCRv5
# server model with TASK_MAX_LOAD=3 overflows device memory.
export CUSTOM_INTER_OP_THREADS_COUNT=1
export CUSTOM_INTRA_OP_THREADS_COUNT=1
export DXRT_DYNAMIC_CPU_THREAD=1
export DXRT_TASK_MAX_LOAD=1
export NFH_INPUT_WORKER_THREADS=1
export NFH_OUTPUT_WORKER_THREADS=1
EOF
    chmod +x "${FASTAPI}/deepx_env.sh"
}

setup_ocr() {
    step "OCR Web：venv + dx-engine 3.3.0 + server 模型"
    export DX_RT_PATH="${DX_RT_SRC}"
    bash "${OCR_PY}/build.sh" --dx_rt "${DX_RT_SRC}"

    local vpy="${FASTAPI}/venv/bin/python"
    [ -x "${vpy}" ] || die "OCR FastAPI venv 未创建"

    if ! "${vpy}" -c 'import dx_engine.capi._pydxrt' 2>/dev/null; then
        echo "dx_engine 未正确链接，按已安装 libdxrt 强制编译 3.3.0 ..."
        local dx_root="${DXRT_INSTALLED_DIR:-/usr/local}"
        [ -e "${dx_root}/lib/libdxrt.so" ] || dx_root=/usr/local
        CMAKE_ARGS="-DDX_ROOT_DIR=${dx_root}" \
            "${FASTAPI}/venv/bin/pip" install --force-reinstall "${DX_RT_SRC}/python_package" \
            || die "编译 dx-engine 3.3.0 失败"
    fi

    local ver
    ver="$("${vpy}" -c 'import dx_engine; print(getattr(dx_engine, "__version__", ""))' 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | tail -1)"
    echo "dx_engine version: ${ver:-unknown}"
    case "${ver}" in
        3.3.0*) ok "dx_engine 3.3.0" ;;
        3.4.*)
            die "检测到 dx-engine 3.4.x。本板驱动是 2.4.1，3.4 需要 ≥2.5.0。请卸掉后只用 v3.3.0 源码重装。"
            ;;
        *) die "未能确认 dx_engine==3.3.0（当前: ${ver:-unknown}）" ;;
    esac

    local det="${FASTAPI}/deepx/engine/model_files/server/det_v5_640.dxnn"
    if [ ! -f "${det}" ]; then
        echo "补下 OCR server 模型: ${SERVER_TAR_URL}"
        mkdir -p "${FASTAPI}/deepx/.temp/download" "${FASTAPI}/deepx/engine/model_files/server"
        local tgz="${FASTAPI}/deepx/.temp/download/server.tar.gz"
        [ -f "${tgz}" ] || curl -fL --retry 5 --retry-delay 3 -o "${tgz}" "${SERVER_TAR_URL}"
        tar -xzf "${tgz}" -C "${FASTAPI}/deepx/engine/model_files/server"
        [ -f "${det}" ] || die "解压后没有 det_v5_640.dxnn"
    fi
    ok "OCR server det_v5_640.dxnn"

    write_ocr_deepx_env
    [ -x "${OCR_PY}/.venv/bin/python" ] || die "Gradio UI venv 未创建"
    ok "OCR UI venv + deepx_env.sh"
}

build_cpp() {
    step "编译 C++ demo（与启动器同一套）"
    bash "${ROOT}/build.sh" --lang cpp --no-ocr-web
    [ -x "${ROOT}/apps/drone/cpp/build/drone_mixformer" ] || die "drone_mixformer 未生成"
    [ -x "${ROOT}/apps/hand-landmark/cpp/build/hand-landmark-pose" ] || die "hand-landmark-pose 未生成"
    ok "C++ 二进制已生成"
}

print_run() {
    step "部署完成。按下面启动（不要预加载 CPU PaddleOCR，不要装 dx-engine==3.4.0）"
    cat <<EOF

  cd ${ROOT}
  source toolchain.env
  export DISPLAY=:0 QT_QPA_PLATFORM=xcb
  export PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True

  ./scripts/run_launcher.sh
  ./scripts/run_ocr_web.sh
  ./scripts/run_hands.sh
  ./scripts/run_drone_1.sh

注意:
  - 必须一致的是 DX-RT ${EXPECTED_DXRT} / dx-engine 3.3.0 / 驱动 ${EXPECTED_DRIVER}，不是 Ubuntu 版本
  - 摄像头当前 ${DX_CAMERA_DEV}（不对就 export DX_CAMERA_IDX=N）
  - OCR 用 NPU + --use-server --lazy-load；不要装 dx-engine==3.4.0
  - Firefly 镜像不要 apt 拆 hold；其他系统按该机包管理器安装依赖即可
  - 不要对含 app.py / ocr_service.py / run.sh 的命令行做泛匹配 pkill
EOF
}

main() {
    echo "Reproduce DX-RT ${EXPECTED_DXRT} demo tree (OS/board need not match the Firefly image)"
    echo "ROOT=${ROOT}"
    check_sdk
    check_host_tools
    setup_assets
    setup_poppler
    setup_dx_rt_src
    setup_launcher_venv
    setup_ocr
    build_cpp
    bash "${ROOT}/scripts/verify_repro.sh"
    print_run
}

main "$@"
