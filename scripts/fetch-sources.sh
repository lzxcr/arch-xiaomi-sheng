#!/usr/bin/env bash
#
# fetch-sources.sh —— 从 ianchb/debian-sheng clone 并提取
# PKGBUILD 引用的本地源文件到对应 pkgs/ 目录。
#
# 用法: ./scripts/fetch-sources.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/config.sh
source "$SCRIPT_DIR/config.sh"

# ── 参数解析 ──────────────────────────────────────────────
LOCAL_SRC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --local) LOCAL_SRC="$2"; shift 2 ;;
    --help)  echo "用法: $0 [--local /path/to/debian-sheng]"; exit 0 ;;
    *)       echo "未知参数: $1"; exit 1 ;;
  esac
done

# ── 获取源文件 ────────────────────────────────────────────
if [ -n "$LOCAL_SRC" ]; then
  SRC_DIR="$LOCAL_SRC"
  echo "==> 使用本地源: $SRC_DIR"
  if [ ! -d "$SRC_DIR/sheng-sensors-files" ]; then
    echo "错误: $SRC_DIR 不是有效的 debian-sheng 仓库目录"
    exit 1
  fi
else
  TMP_CLONE="/tmp/debian-sheng-$$"
  cleanup() { rm -rf "$TMP_CLONE"; }
  trap cleanup EXIT
  echo "==> 克隆 ianchb/debian-sheng ..."
  git clone --depth=1 "https://github.com/ianchb/debian-sheng.git" "$TMP_CLONE"
  SRC_DIR="$TMP_CLONE"
fi

echo "==> 提取文件到 pkgs/ ..."

# 1. adsprpcd-sensorspd.service → pkgs/fastrpc/
mkdir -p "$PKG_DIR/fastrpc"
if [ -f "$SRC_DIR/patches/adsprpcd-sensorspd.service" ]; then
  cp "$SRC_DIR/patches/adsprpcd-sensorspd.service" \
     "$PKG_DIR/fastrpc/adsprpcd-sensorspd.service"
  echo "  ✓ fastrpc/adsprpcd-sensorspd.service"
else
  echo "  ! fastrpc/adsprpcd-sensorspd.service 未找到，已跳过"
fi

# 2. wait_for_qmi_service.patch → pkgs/libssc/
mkdir -p "$PKG_DIR/libssc"
if [ -f "$SRC_DIR/patches/wait_for_qmi_service.patch" ]; then
  cp "$SRC_DIR/patches/wait_for_qmi_service.patch" \
     "$PKG_DIR/libssc/wait_for_qmi_service.patch"
  echo "  ✓ libssc/wait_for_qmi_service.patch"
else
  echo "  ! libssc/wait_for_qmi_service.patch 未找到，已跳过"
fi

# 3. sheng-sensors-files/ → pkgs/xiaomi-sheng-sensors/
mkdir -p "$PKG_DIR/xiaomi-sheng-sensors"
if [ -d "$SRC_DIR/sheng-sensors-files" ]; then
  rm -rf "$PKG_DIR/xiaomi-sheng-sensors/sheng-sensors-files"
  cp -r "$SRC_DIR/sheng-sensors-files" \
     "$PKG_DIR/xiaomi-sheng-sensors/sheng-sensors-files"
  echo "  ✓ xiaomi-sheng-sensors/sheng-sensors-files/ (共 $(find "$PKG_DIR/xiaomi-sheng-sensors/sheng-sensors-files" -type f | wc -l) 个文件)"
else
  echo "  ! xiaomi-sheng-sensors/sheng-sensors-files/ 未找到，已跳过"
fi

echo "==> 完成。"
