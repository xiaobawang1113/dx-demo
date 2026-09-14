#!/bin/bash
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Desktop / XFCE launches often have no DISPLAY in a login-shell profile.
if [ -f "${ROOT_DIR}/toolchain.env" ]; then
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/toolchain.env"
fi
# OCR sets this to 1 in deepx_env.sh. A leftover value of 1 here is inherited
# by every demo the launcher starts and cuts NPU pipeline buffers to 1/3.
unset DXRT_TASK_MAX_LOAD
export DISPLAY="${DISPLAY:-:0}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
cd "$(dirname "$0")/../launcher"

# Load top-level configuration
if [ -f "${ROOT_DIR}/config.sh" ]; then
    source "${ROOT_DIR}/config.sh"
fi

# Kill any existing processes
../scripts/kill_all.sh

# Activate virtual environment
source ../.venv/bin/activate

# Firefly Qt 5.15 was built without some OpenGL classes; Ubuntu python3-pyqt5
# then fails to import QtGui (QOpenGLTimeMonitor). Fall back to scripts/*.sh.
if ! python -c 'from PyQt5.QtWidgets import QApplication' 2>/dev/null; then
    echo "PyQt5 GUI launcher is unavailable on this Firefly image (QtGui ABI mismatch)."
    echo "Start demos directly, for example:"
    echo "  ${ROOT_DIR}/scripts/run_yolo26_3_video.sh"
    echo "  ${ROOT_DIR}/scripts/run_depth_video.sh"
    echo "  ${ROOT_DIR}/scripts/run_automotive_pidnet.sh"
    exit 1
fi

# Run the launcher GUI
python main.py
