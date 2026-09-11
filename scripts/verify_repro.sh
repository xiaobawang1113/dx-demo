#!/usr/bin/env bash
# Check that this tree matches the Firefly RK3588 + DX-RT 3.3.0 working board.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/toolchain.env"

EXPECTED_DRIVER="2.4.1"
FAIL=0
ok() { echo "OK   $*"; }
bad() { echo "FAIL $*"; FAIL=1; }
warn() { echo "WARN $*"; }

echo "ROOT=${ROOT}"
echo

if command -v dxrt-cli >/dev/null 2>&1; then
    info="$(dxrt-cli -s 2>&1 || true)"
    echo "${info}" | head -20
    echo
    echo "${info}" | grep -qE 'DXRT v3\.3\.0|DX-RT[[:space:]]*3\.3\.0' \
        && ok "DX-RT 3.3.0" \
        || bad "DX-RT 不是 3.3.0（另一台机器必须装同一套 SDK）"
    if echo "${info}" | grep -q "${EXPECTED_DRIVER}"; then
        ok "RT driver ${EXPECTED_DRIVER}"
    elif echo "${info}" | grep -qi 'Device not found'; then
        warn "dxrt-cli 未能列出驱动版本（NPU 未识别）。有卡时应为 ${EXPECTED_DRIVER}"
    else
        warn "未看到 RT driver ${EXPECTED_DRIVER}；驱动不同则 .dxnn / dx-engine 会对不上"
    fi
else
    bad "找不到 dxrt-cli（SDK 未装进 PATH）"
fi

if [ -n "${DXRT_INSTALLED_DIR:-}" ] && [ -e "${DXRT_INSTALLED_DIR}/lib/libdxrt.so" ]; then
    ok "libdxrt ${DXRT_INSTALLED_DIR}/lib/libdxrt.so"
else
    bad "找不到 libdxrt.so（设 DXRT_INSTALLED_DIR）"
fi
[ -e /usr/local/lib/libonnxruntime.so ] || [ -e "${ONNXRUNTIME_ROOT}/lib/libonnxruntime.so" ] \
    && ok "libonnxruntime" \
    || bad "找不到 libonnxruntime（drone MixFormer 需要）"

[ -d "${ROOT}/workspace/models" ] && [ -d "${ROOT}/workspace/videos" ] \
    && ok "workspace 模型与视频" \
    || bad "缺 workspace/（先跑 setup_assets.sh 或 scripts/setup_repro.sh）"

[ -x "${ROOT}/.venv/bin/python" ] && ok "启动器 .venv" || bad "缺 .venv（setup_env.sh）"
if [ -x "${ROOT}/.venv/bin/python" ]; then
    "${ROOT}/.venv/bin/python" -c 'from PyQt5.QtWidgets import QApplication' 2>/dev/null \
        && ok "PyQt5（启动器）" \
        || warn "PyQt5 导入失败。有系统 python3-pyqt5 时用 --system-site-packages；其他系统可 pip 装 PyQt5"
fi

FASTAPI="${ROOT}/apps/paddle-ocr-web/python/PaddleOCR-deepx/deploy/fastapi"
VPY="${FASTAPI}/venv/bin/python"
if [ -x "${VPY}" ]; then
    ok "OCR FastAPI venv"
    ver="$("${VPY}" -c 'import dx_engine; print(getattr(dx_engine, "__version__", ""))' 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | tail -1)"
    case "${ver}" in
        3.3.0*) ok "dx_engine ${ver}" ;;
        3.4.*) bad "dx_engine ${ver}：本板驱动 2.4.1，禁止 3.4.x（需要驱动 ≥2.5.0）" ;;
        *) bad "OCR venv 里没有 dx_engine 3.3.0（当前: ${ver:-未安装}）" ;;
    esac
    "${VPY}" -c 'import dx_engine.capi._pydxrt' 2>/dev/null \
        && ok "dx_engine.capi._pydxrt" \
        || bad "dx_engine 扩展未链到 libdxrt（不要用未安装的 dx_rt 源码树当 DX_ROOT_DIR）"
else
    bad "缺 OCR FastAPI venv"
fi
[ -x "${ROOT}/apps/paddle-ocr-web/python/.venv/bin/python" ] && ok "OCR Gradio venv" || bad "缺 OCR UI venv"
[ -f "${FASTAPI}/deepx/engine/model_files/server/det_v5_640.dxnn" ] \
    && ok "OCR server det_v5_640.dxnn" \
    || bad "缺 OCR NPU 模型（setup_deepx_models / setup_repro）"
if [ -f "${FASTAPI}/deepx_env.sh" ]; then
    grep -q 'DXRT_TASK_MAX_LOAD=1' "${FASTAPI}/deepx_env.sh" \
        && ok "deepx_env.sh TASK_MAX_LOAD=1" \
        || bad "deepx_env.sh 的 TASK_MAX_LOAD 必须是 1（M1 约 1.92GiB，3 会撑爆）"
else
    bad "缺 deepx_env.sh（run.sh 看不到它就会走 CPU；请保持 NPU 路径）"
fi
POP="${ROOT}/apps/paddle-ocr-web/python/.cache/poppler-utils-22.02.0-2ubuntu0.3/usr/bin/pdftoppm"
if [ -x "${POP}" ]; then
    ok "poppler pdftoppm（缓存）"
elif command -v pdftoppm >/dev/null 2>&1; then
    ok "poppler pdftoppm（系统 $(command -v pdftoppm)）"
else
    warn "没有 pdftoppm：图片 OCR 可用，PDF 需要目标机安装 poppler-utils"
fi

[ -x "${ROOT}/apps/drone/cpp/build/drone_mixformer" ] && ok "drone_mixformer" \
    || bad "未编译 drone_mixformer"
[ -x "${ROOT}/apps/hand-landmark/cpp/build/hand-landmark-pose" ] && ok "hand-landmark-pose" \
    || bad "未编译 hand-landmark-pose"

if [ -e "${DX_CAMERA_DEV}" ]; then
    ok "摄像头 ${DX_CAMERA_DEV}"
else
    warn "没有 ${DX_CAMERA_DEV}（手势摄像头会失败；可用 v4l2-ctl --list-devices 改 DX_CAMERA_IDX）"
fi

echo
if [ "${FAIL}" -ne 0 ]; then
    echo "复现检查未通过。先跑: ${ROOT}/scripts/setup_repro.sh"
    exit 1
fi
echo "复现检查通过。接着:"
echo "  source ${ROOT}/toolchain.env"
echo "  export DISPLAY=:0 QT_QPA_PLATFORM=xcb PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True"
echo "  ${ROOT}/scripts/run_launcher.sh"
exit 0
