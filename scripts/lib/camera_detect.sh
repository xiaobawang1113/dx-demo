# Camera auto-detect for dx-demo. Source after profile/*.env.
# User overrides (win over auto): DX_CAMERA_IDX, DX_CAMERA_DEV, DX_CAMERA_BACKEND, DX_CAMERA_FOURCC

dx_camera_resolve() {
    local idx="${DX_CAMERA_IDX:-auto}"
    local backend="${DX_CAMERA_BACKEND:-auto}"
    local fourcc="${DX_CAMERA_FOURCC:-auto}"

    if [ "${backend}" = "auto" ]; then
        if [ "$(uname -s)" = "Linux" ]; then
            backend=v4l2
        else
            backend=any
        fi
    fi

    if [ "${idx}" != "auto" ] && [ -n "${idx}" ]; then
        export DX_CAMERA_IDX="${idx}"
        export DX_CAMERA_DEV="${DX_CAMERA_DEV:-/dev/video${idx}}"
        export DX_CAMERA_BACKEND="${backend}"
        if [ "${fourcc}" != "auto" ] && [ -n "${fourcc}" ]; then
            export DX_CAMERA_FOURCC="${fourcc}"
        fi
        return 0
    fi

    local picked_dev="" picked_idx="" picked_fourcc=""
    if command -v v4l2-ctl >/dev/null 2>&1; then
        picked_dev="$(dx_camera_pick_v4l2_device)"
        if [ -n "${picked_dev}" ]; then
            picked_idx="${picked_dev#/dev/video}"
            if [ "${fourcc}" = "auto" ]; then
                picked_fourcc="$(dx_camera_pick_fourcc "${picked_dev}")"
            else
                picked_fourcc="${fourcc}"
            fi
        fi
    fi

    if [ -z "${picked_idx}" ]; then
        picked_idx="${DX_CAMERA_IDX_FALLBACK:-0}"
        picked_dev="/dev/video${picked_idx}"
        if [ "${fourcc}" != "auto" ] && [ -n "${fourcc}" ]; then
            picked_fourcc="${fourcc}"
        elif [ -n "${DX_CAMERA_FOURCC:-}" ] && [ "${DX_CAMERA_FOURCC}" != "auto" ]; then
            picked_fourcc="${DX_CAMERA_FOURCC}"
        else
            picked_fourcc="MJPG"
        fi
        echo "WARN: camera auto-detect: v4l2-ctl missing or no UVC device; using ${picked_dev} fourcc=${picked_fourcc}" >&2
    fi

    export DX_CAMERA_IDX="${picked_idx}"
    export DX_CAMERA_DEV="${picked_dev}"
    export DX_CAMERA_BACKEND="${backend}"
    [ -n "${picked_fourcc}" ] && export DX_CAMERA_FOURCC="${picked_fourcc}"
}

dx_camera_pick_v4l2_device() {
    local skip_re="${DX_CAMERA_SKIP_NAME_REGEX:-hdmirx|hdmi}"
    local dev name card driver
    for dev in /dev/video*; do
        [ -e "${dev}" ] || continue
        name="$(v4l2-ctl -d "${dev}" --info 2>/dev/null | grep -i 'Card type' | head -1 || true)"
        card="$(v4l2-ctl -d "${dev}" --info 2>/dev/null | grep -i 'Driver name' | head -1 || true)"
        driver="${card#*:}"
        driver="${driver#*driver}"
        driver="$(echo "${driver}" | tr -d ' \t:' | tr '[:upper:]' '[:lower:]')"
        local blob
        blob="$(echo "${name} ${card}" | tr '[:upper:]' '[:lower:]')"
        if echo "${blob}" | grep -qiE "${skip_re}"; then
            continue
        fi
        # Need video capture capability (not metadata-only node).
        if ! v4l2-ctl -d "${dev}" --list-formats 2>/dev/null | grep -qiE 'MJPG|YUYV|H264|RGB|BGR|GREY'; then
            continue
        fi
        echo "${dev}"
        return 0
    done
    return 1
}

dx_camera_pick_fourcc() {
    local dev="$1"
    local formats
    formats="$(v4l2-ctl -d "${dev}" --list-formats-ext 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
    if echo "${formats}" | grep -q "'mjpg'"; then
        echo "MJPG"
        return
    fi
    if echo "${formats}" | grep -q "'yuyv'"; then
        echo "YUYV"
        return
    fi
    if echo "${formats}" | grep -q "'h264'"; then
        echo "H264"
        return
    fi
    echo "MJPG"
}
