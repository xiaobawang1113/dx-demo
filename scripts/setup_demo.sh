#!/usr/bin/env bash
# Daily demo deploy — Compatible Mode (SDK 2.3.x), any RK3588 vendor / customer device.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/toolchain.env"
# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/dxrt_compat.sh"

OCR_PY="${ROOT}/apps/paddle-ocr-web/python"
FASTAPI="${OCR_PY}/PaddleOCR-deepx/deploy/fastapi"
CACHE="${OCR_PY}/.cache"
POPPLER_VER="22.02.0-2ubuntu0.3"
POPPLER_DIR="${CACHE}/poppler-utils-${POPPLER_VER}"
SERVER_TAR_URL="${DX_OCR_SERVER_URL:-https://sdk.deepx.ai/res/assets/dx_baidu_PPOCR/server.tar.gz}"

SKIP_CPP=false
SKIP_OCR=false
while (( $# )); do
    case "$1" in
        --skip-cpp) SKIP_CPP=true; shift;;
        --ocr-only) SKIP_CPP=true; shift;;
        --skip-ocr) SKIP_OCR=true; shift;;
        -h|--help)
            echo "Usage: $0 [--skip-cpp|--ocr-only] [--skip-ocr]"
            exit 0;;
        *) echo "Unknown: $1"; exit 1;;
    esac
done

die() { echo "ERROR: $*" >&2; exit 1; }
ok() { echo "OK  $*"; }
step() { echo; echo "======== $* ========"; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "缺少: $1（请在本机安装构建依赖）"
}

check_sdk_compatible() {
    step "Compatible Mode：DX-RT / Driver / libdxrt"
    need_cmd dxrt-cli
    dxrt_compat_print_status
    echo
    dxrt_compat_check_dxrt || die "DXRT 3.x 不可用。请先安装 DEEPX SDK 2.3.x 系列。"
    dxrt_compat_check_libdxrt || die "找不到 libdxrt.so"
    if ! dxrt_compat_check_driver; then
        echo "WARN: Driver 未在 dxrt-cli -s 中识别；继续部署，运行时再查 NPU。"
    fi
    if ! dxrt_compat_check_npu; then
        echo "WARN: NPU 未识别；可先完成编译，插卡/驱动就绪后再跑推理。"
    fi
    ok "DXRT $(dxrt_compat_dxrt_version) @ ${DXRT_INSTALLED_DIR:-?}"
}

check_host_tools() {
    step "编译工具"
    local missing=()
    for c in gcc g++ cmake make pkg-config python3 curl tar git; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    pkg-config --exists opencv4 2>/dev/null || pkg-config --exists opencv 2>/dev/null \
        || missing+=("libopencv-dev")
    pkg-config --exists Qt5Widgets 2>/dev/null || missing+=("qtbase5-dev")
    [ "${#missing[@]}" -eq 0 ] || die "缺少: ${missing[*]}"
    ok "工具链就绪"
}

setup_assets() {
    step "workspace 资源"
    bash "${ROOT}/setup_assets.sh"
    ok "setup_assets.sh"
}

setup_poppler() {
    step "pdftoppm（可选 PDF OCR）"
    mkdir -p "${CACHE}"
    if [ -x "${POPPLER_DIR}/usr/bin/pdftoppm" ]; then
        ok "缓存 poppler"
        return
    fi
    local os_id="" os_ver=""
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        os_id="$(. /etc/os-release && echo "${ID:-}")"
        os_ver="$(. /etc/os-release && echo "${VERSION_ID:-}")"
    fi
    if [ "$(uname -m)" = "aarch64" ] && [ "${os_id}" = "ubuntu" ] && [ "${os_ver}" = "22.04" ]; then
        local deb="${CACHE}/poppler-utils_${POPPLER_VER}_arm64.deb"
        local url="http://ports.ubuntu.com/ubuntu-ports/pool/main/p/poppler/poppler-utils_${POPPLER_VER}_arm64.deb"
        [ -f "${deb}" ] || curl -fL --retry 5 -o "${deb}" "${url}"
        mkdir -p "${POPPLER_DIR}"
        dpkg-deb -x "${deb}" "${POPPLER_DIR}"
        ok "Ubuntu 22.04 aarch64 poppler 缓存"
        return
    fi
    command -v pdftoppm >/dev/null 2>&1 && ok "系统 pdftoppm" || echo "WARN: 无 pdftoppm（仅影响 PDF）"
}

ensure_dx_rt_src() {
    local tag ver tgz top dest
    tag="$(dxrt_compat_dxrt_tag)"
    ver="${tag#v}"
    dest="${CACHE}/dx_rt-${ver}"
    if [ -f "${dest}/python_package/pyproject.toml" ] || [ -f "${dest}/python_package/setup.py" ]; then
        printf '%s' "${dest}"
        return 0
    fi
    step "dx_rt 源码（tag ${tag}，与当前 DX-RT 对齐编译 dx-engine）"
    tgz="${CACHE}/dx_rt-${ver}.tar.gz"
    if [ ! -f "${tgz}" ]; then
        curl -fL --retry 5 -o "${tgz}" \
            "https://github.com/DEEPX-AI/dx_rt/archive/refs/tags/${tag}.tar.gz" \
            || die "下载 dx_rt ${tag} 失败（可 export DX_RT_PATH=/path/to/dx_rt）"
    fi
    rm -rf "${CACHE}/dx_rt-extract-${ver}"
    mkdir -p "${CACHE}/dx_rt-extract-${ver}"
    tar -xzf "${tgz}" -C "${CACHE}/dx_rt-extract-${ver}"
    top="$(find "${CACHE}/dx_rt-extract-${ver}" -maxdepth 1 -type d -name 'dx_rt-*' | head -1)"
    [ -n "${top}" ] || die "tarball 无效"
    rm -rf "${dest}"
    mv "${top}" "${dest}"
    ok "dx_rt ${tag} -> ${dest}"
    printf '%s' "${dest}"
}

setup_launcher_venv() {
    step "启动器 .venv"
    bash "${ROOT}/setup_env.sh"
    [ -x "${ROOT}/.venv/bin/python" ] || die ".venv 失败"
    ok "launcher"
}

setup_ocr() {
    step "OCR Web"
    bash "${ROOT}/apps/paddle-ocr-web/fetch_upstream.sh" 2>/dev/null || true
    bash "${ROOT}/apps/paddle-ocr-web/apply_board_overlay.sh" 2>/dev/null || true

    local dx_rt_path="${DX_RT_PATH:-}"
    if [ -z "${dx_rt_path}" ]; then
        dx_rt_path="$(ensure_dx_rt_src)"
    fi
    export DX_RT_PATH="${dx_rt_path}"
    bash "${OCR_PY}/build.sh" --dx_rt "${dx_rt_path}"

    local vpy="${FASTAPI}/venv/bin/python"
    [ -x "${vpy}" ] || die "OCR FastAPI venv 未创建"

    if ! dxrt_compat_check_dx_engine "${vpy}"; then
        local dx_root="${DXRT_INSTALLED_DIR:-/usr/local}"
        [ -e "${dx_root}/lib/libdxrt.so" ] || dx_root=/usr/local
        echo "从 ${dx_rt_path}/python_package 编译 dx-engine ..."
        CMAKE_ARGS="-DDX_ROOT_DIR=${dx_root}" \
            "${FASTAPI}/venv/bin/pip" install --force-reinstall "${dx_rt_path}/python_package" \
            || die "dx-engine 编译失败"
    fi
    dxrt_compat_check_dx_engine "${vpy}" || die "dx-engine 仍不可 import"

    local det="${FASTAPI}/deepx/engine/model_files/server/det_v5_640.dxnn"
    if [ ! -f "${det}" ]; then
        mkdir -p "${FASTAPI}/deepx/.temp/download" "${FASTAPI}/deepx/engine/model_files/server"
        local tgz="${FASTAPI}/deepx/.temp/download/server.tar.gz"
        [ -f "${tgz}" ] || curl -fL --retry 5 -o "${tgz}" "${SERVER_TAR_URL}"
        tar -xzf "${tgz}" -C "${FASTAPI}/deepx/engine/model_files/server"
    fi
    [ -f "${det}" ] || die "缺少 det_v5_640.dxnn"

    bash "${ROOT}/apps/paddle-ocr-web/apply_board_overlay.sh"
    chmod +x "${FASTAPI}/deepx_env.sh" 2>/dev/null || true
    ok "OCR + board overlay"
}

build_cpp() {
    step "C++ demos"
    bash "${ROOT}/build.sh" --lang cpp --no-ocr-web
    ok "build.sh cpp"
}

main() {
    echo "setup_demo.sh — Compatible Mode (SDK 2.3.x)"
    check_sdk_compatible
    check_host_tools
    setup_assets
    setup_poppler
    setup_launcher_venv
    if [ "${SKIP_OCR}" = false ]; then
        setup_ocr
    fi
    if [ "${SKIP_CPP}" = false ]; then
        build_cpp
    fi
    bash "${ROOT}/scripts/verify_compatible.sh" || true
    echo
    echo "完成。启动: source toolchain.env && ./scripts/run_launcher.sh"
}

main "$@"
