#!/usr/bin/env bash
#
# install-chroot.sh —— 将已构建的包安装到 clean chroot（供层级依赖构建）
# 用法: ./scripts/install-chroot.sh <package-file>
#   <package-file>: 指向 *.pkg.tar.* 的路径
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=scripts/config.sh
source "$SCRIPT_DIR/config.sh"

if [ $# -lt 1 ]; then
    echo "用法: $0 <package-file>" >&2
    exit 1
fi

PKG_FILE="$(realpath "$1")"

if [ ! -f "$PKG_FILE" ]; then
    echo "错误: 文件不存在 $PKG_FILE" >&2
    exit 1
fi

if [ ! -d "$BUILD_CHROOT/root" ]; then
    echo "错误: chroot 不存在于 $BUILD_CHROOT/root，请先运行 build-pkgs.sh" >&2
    exit 1
fi

echo "==> 安装 $(basename "$PKG_FILE") 到 chroot ..."
sudo arch-nspawn "$BUILD_CHROOT/root" \
    pacman -U --noconfirm "$PKG_FILE" 2>&1 | tail -1
echo "  ✓"
