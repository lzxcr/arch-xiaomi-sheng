#!/usr/bin/env bash
#
# clean.sh —— 清理所有构建产物，保持工作区干净
# 用法: ./scripts/clean.sh [--keep-cache]
#   --keep-cache: 保留已下载的源码缓存（归档、deb 与 VCS 镜像）
#

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

KEEP_CACHE=0

while (($# > 0)); do
  case "$1" in
    --keep-cache) KEEP_CACHE=1 ;;
    -h|--help)
      printf '用法: clean.sh [--keep-cache]\n'
      exit 0
      ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done

msg "清理 pkgs/*/ 下构建产物 ..."

for pkgdir in "$PKG_DIR"/*/; do
  # 构建中间目录（makepkg 的 $srcdir/$pkgdir）
  rm -rf "$pkgdir/src" "$pkgdir/pkg"

  # 构建产物（makepkg 输出）
  rm -f "$pkgdir"*.pkg.tar.*

  # 本地打包的源文件（由 package-files.sh 重新生成）
  rm -f "$pkgdir/files.tar.gz"

  # 下载的远程源码缓存（默认删除；--keep-cache 时保留）
  if ((KEEP_CACHE == 0)); then
    rm -f \
      "$pkgdir"*.tar.gz \
      "$pkgdir"*.tar.xz \
      "$pkgdir"*.deb \
      "$pkgdir"*.deb.part
    rm -rf \
      "$pkgdir/hexagonrpc" \
      "$pkgdir/sheng-firmware" \
      "$pkgdir/sheng_devauth"
  fi
done

msg "清理 out/ ..."
rm -rf "$OUT_PKGS_DIR" "$OUT_REPO_DIR" "$OUT_ROOTFS_DIR" "$OUT_DIR/sheng-repo.conf"

msg "完成。"
