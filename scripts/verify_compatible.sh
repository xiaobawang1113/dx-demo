#!/usr/bin/env bash
# Compatible Mode (SDK 2.3.x): customer RK3588 / daily demo — not a frozen lab image.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/toolchain.env"
# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/dxrt_compat.sh"

FAIL=0
ok() { echo "OK   $*"; }
bad() { echo "FAIL $*"; FAIL=1; }
warn() { echo "WARN $*"; }

echo "Compatible Mode — SDK 2.3.x / DEEPX demo deploy"
echo "ROOT=${ROOT}"
echo

if command -v dxrt-cli >/dev/null 2>&1; then
    dxrt_compat_print_status
    echo
else
    bad "找不到 dxrt-cli（请先安装 DEEPX SDK 2.3.x 并把 dxrt-cli 加入 PATH）"
fi

if dxrt_compat_check_dxrt; then
    ok "DXRT compatible ($(dxrt_compat_dxrt_version))"
else
    bad "DXRT 不可用或版本无法识别（需要 DXRT 3.x，对应 SDK 2.3.x 产品线）"
fi

if dxrt_compat_check_driver; then
    ok "Driver compatible"
else
    warn "Driver 信息未识别（NPU 未枚举或 dxrt-cli 输出不完整；有卡时建议先解决 PCIe/驱动）"
fi

if dxrt_compat_check_libdxrt; then
    ok "libdxrt 存在 (${DXRT_INSTALLED_DIR:-/usr/local}/lib/libdxrt.so)"
else
    bad "libdxrt 不存在（export DXRT_INSTALLED_DIR=含 lib/libdxrt.so 的前缀）"
fi

if dxrt_compat_check_npu; then
    ok "NPU 存在"
else
    warn "NPU 未识别（推理 demo 需要设备；纯编译检查可忽略）"
fi

FASTAPI="${ROOT}/apps/paddle-ocr-web/python/PaddleOCR-deepx/deploy/fastapi"
VPY="${FASTAPI}/venv/bin/python"
DET="${FASTAPI}/deepx/engine/model_files/server/det_v5_640.dxnn"

if [ -x "${VPY}" ]; then
    if dxrt_compat_check_dx_engine "${VPY}"; then
        eng="$(dxrt_compat_dx_engine_version "${VPY}")"
        ok "dx-engine 可 import (${eng:-?})"
        if ! dxrt_compat_engine_matches_runtime "${eng}"; then
            warn "dx-engine ${eng} 与 DX-RT $(dxrt_compat_dxrt_version) 可能不完全同版；优先用 libdxrt-bin  wheel 或同 tag 的 dx_rt 源码编译"
        fi
    else
        bad "dx-engine 不可 import（跑 setup_demo.sh / python/build.sh，勿混用 PyPI 与 libdxrt 不匹配的 wheel）"
    fi
else
    warn "OCR venv 未建（可选：./scripts/setup_demo.sh --ocr-only 或 ./apps/paddle-ocr-web/python/build.sh）"
fi

if dxrt_compat_check_ocr_model_files "${DET}"; then
    ok "模型可 load（det_v5_640.dxnn 在盘）"
else
    warn "OCR server 模型未下载（./setup_assets.sh + OCR build 会拉 .dxnn）"
fi

[ -d "${ROOT}/workspace/models" ] && ok "workspace 模型目录" || warn "缺 workspace/models（./setup_assets.sh）"
[ -x "${ROOT}/.venv/bin/python" ] && ok "启动器 .venv" || warn "缺 launcher .venv（./setup_env.sh）"

if [ -f "${FASTAPI}/deepx_env.sh" ]; then
    grep -q 'DXRT_TASK_MAX_LOAD=1' "${FASTAPI}/deepx_env.sh" \
        && ok "OCR deepx_env（M1 推荐 TASK_MAX_LOAD=1）" \
        || warn "deepx_env.sh 未设 TASK_MAX_LOAD=1；小显存 M1 上 OCR 可能 OOM"
else
    warn "无 deepx_env.sh（OCR 可能走 CPU 路径）"
fi

echo
if [ "${FAIL}" -ne 0 ]; then
    echo "兼容检查未通过（阻塞项见 FAIL）。部署: ${ROOT}/scripts/setup_demo.sh"
    exit 1
fi
echo "兼容检查通过（WARN 可按现场忽略）。启动:"
echo "  source ${ROOT}/toolchain.env && ${ROOT}/scripts/run_launcher.sh"
exit 0
