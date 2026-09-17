# Shared DEEPX SDK 2.3.x compatible-mode checks (source from bash scripts).
# Goal: customer RK3588 boards / daily demo deploy — not a single pinned lab image.

# shellcheck shell=bash

_dxrt_compat_info=""
_dxrt_compat_dxrt_ver=""
_dxrt_compat_driver_ver=""

dxrt_compat_refresh() {
    _dxrt_compat_info=""
    _dxrt_compat_dxrt_ver=""
    _dxrt_compat_driver_ver=""
    if ! command -v dxrt-cli >/dev/null 2>&1; then
        return 1
    fi
    _dxrt_compat_info="$(dxrt-cli -s 2>&1 || true)"
    _dxrt_compat_dxrt_ver="$(echo "${_dxrt_compat_info}" | grep -oE 'DXRT v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/DXRT v//')"
    if [ -z "${_dxrt_compat_dxrt_ver}" ]; then
        _dxrt_compat_dxrt_ver="$(echo "${_dxrt_compat_info}" | grep -oE 'DX-RT[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $2}')"
    fi
    _dxrt_compat_driver_ver="$(echo "${_dxrt_compat_info}" | grep -oE '(RT )?[Dd]river[^0-9]*[0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    return 0
}

dxrt_compat_print_status() {
    dxrt_compat_refresh || true
    if [ -n "${_dxrt_compat_info}" ]; then
        echo "${_dxrt_compat_info}" | head -25
    fi
}

# DX-RT runtime present and version looks like SDK 2.3.x line (DXRT 3.x).
dxrt_compat_check_dxrt() {
    dxrt_compat_refresh || return 1
    [ -n "${_dxrt_compat_dxrt_ver}" ] || return 1
    local major minor
    major="${_dxrt_compat_dxrt_ver%%.*}"
    minor="$(echo "${_dxrt_compat_dxrt_ver}" | cut -d. -f2)"
    [ "${major}" = "3" ] && [ -n "${minor}" ] || return 1
    return 0
}

dxrt_compat_check_driver() {
    dxrt_compat_refresh || return 1
    [ -n "${_dxrt_compat_driver_ver}" ] && return 0
    # Some images only show driver after NPU enumerates
    echo "${_dxrt_compat_info}" | grep -qiE 'driver|firmware|FW' && return 0
    return 1
}

dxrt_compat_check_libdxrt() {
    local d
    for d in "${DXRT_INSTALLED_DIR:-}" /usr/local /usr; do
        [ -n "${d}" ] && [ -e "${d}/lib/libdxrt.so" ] && return 0
    done
    [ -e /usr/local/lib/libdxrt.so ] || [ -e /usr/lib/libdxrt.so ]
}

dxrt_compat_check_npu() {
    dxrt_compat_refresh || return 1
    if echo "${_dxrt_compat_info}" | grep -qi 'Device not found'; then
        return 1
    fi
    echo "${_dxrt_compat_info}" | grep -qiE 'M1|NPU|device|core|PCIe' && return 0
    # No explicit error and dxrt-cli succeeded
    [ -n "${_dxrt_compat_dxrt_ver}" ]
}

dxrt_compat_dxrt_version() {
    dxrt_compat_refresh || true
    echo "${_dxrt_compat_dxrt_ver}"
}

# Tag for dx_rt python_package / github archive (e.g. 3.3.0 -> v3.3.0).
dxrt_compat_dxrt_tag() {
    local v
    v="$(dxrt_compat_dxrt_version)"
    if [ -n "${v}" ]; then
        echo "v${v}"
        return
    fi
    echo "${DX_RT_TAG:-v3.3.0}"
}

dxrt_compat_check_dx_engine() {
    local py="$1"
    [ -x "${py}" ] || return 1
    "${py}" -c 'import dx_engine.capi._pydxrt' >/dev/null 2>&1
}

dxrt_compat_dx_engine_version() {
    local py="$1"
    [ -x "${py}" ] || return 1
    "${py}" -c 'import dx_engine; print(getattr(dx_engine, "__version__", ""))' 2>/dev/null \
        | grep -E '^[0-9]+\.[0-9]+' | tail -1
}

# Heuristic: dx-engine major.minor should match DX-RT (warn-only helper).
dxrt_compat_engine_matches_runtime() {
    local eng="$1"
    local rt
    rt="$(dxrt_compat_dxrt_version)"
    [ -n "${eng}" ] && [ -n "${rt}" ] || return 0
    local eng_mm="${eng%%.*}.$(echo "${eng}" | cut -d. -f2)"
    local rt_mm="${rt%%.*}.$(echo "${rt}" | cut -d. -f2)"
    [ "${eng_mm}" = "${rt_mm}" ] && return 0
    eng_maj="${eng%%.*}"
    rt_maj="${rt%%.*}"
    [ "${eng_maj}" = "${rt_maj}" ]
}

dxrt_compat_check_ocr_model_files() {
    local det="$1"
    [ -f "${det}" ]
}
