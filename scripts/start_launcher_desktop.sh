#!/bin/bash
# XFCE desktop entry wrapper: keep a log and surface failures.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "${ROOT_DIR}/toolchain.env" ]; then
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/toolchain.env"
fi
unset DXRT_TASK_MAX_LOAD
export DISPLAY="${DISPLAY:-:0}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

LOG="${TMPDIR:-/tmp}/dx-demo-launcher.log"
{
    echo "==== $(date -Iseconds) uid=$(id -u) DISPLAY=${DISPLAY} ===="
} >>"${LOG}"

"${ROOT_DIR}/scripts/run_launcher.sh" >>"${LOG}" 2>&1
rc=$?
echo "exit ${rc}" >>"${LOG}"

if [ "${rc}" -ne 0 ]; then
    zenity --error --title="DEEPX Demo" --width=360 \
        --text="启动失败 (exit ${rc})。\n日志: ${LOG}" 2>/dev/null || true
fi
exit "${rc}"
