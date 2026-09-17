# Board profiles

`source toolchain.env` 会按顺序：

1. 自动选 profile（或 `export DX_DEMO_PROFILE=validated-firefly|rk3588|generic`）
2. 加载 `profile/<name>.env`
3. 运行 `scripts/lib/camera_detect.sh` 解析摄像头

## 摄像头变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `DX_CAMERA_IDX` | `auto` | 数字索引，或 `auto` 用 v4l2 挑 UVC |
| `DX_CAMERA_BACKEND` | `auto` | Linux 上 `auto` → `v4l2` |
| `DX_CAMERA_FOURCC` | `auto` | 在设备支持时优先 `MJPG`，否则 `YUYV` |
| `DX_CAMERA_DEV` | （自动） | 如 `/dev/video1` |

用户 override 示例：

```bash
export DX_DEMO_PROFILE=rk3588
export DX_CAMERA_IDX=2
export DX_CAMERA_FOURCC=YUYV
source toolchain.env
./scripts/dx_camera_info.sh
```

## 文件

| 文件 | 用途 |
| --- | --- |
| `generic.env` | 通用 PC / 板卡 |
| `rk3588.env` | RK3588，跳过 HDMI RX 节点 |
| `validated-firefly.env` | Firefly 实机验证，默认 MJPG |
