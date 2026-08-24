#!/usr/bin/env bash
#
# clean.sh —— 清理所有构建产物，保持工作区干净
# 用法: ./scripts/clean.sh [--keep-cache]
#   --keep-cache: 保留已下载的源码缓存（*.tar.gz, *.deb）
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

KEEP_CACHE=0
[[ "${1:-}" = "--keep-cache" ]] && KEEP_CACHE=1

msg() { echo -e "\033[1;34m==>\033[0m $*"; }

cd "$PROJECT_DIR"

msg "清理 pkgs/*/ 下构建产物 ..."

for pkgdir in pkgs/*/; do
    # 构建中间目录（makepkg 的 $srcdir/$pkgdir）
    rm -rf "$pkgdir/src" "$pkgdir/pkg"

    # 构建产物（.pkg.tar.* 包文件）
    rm -f "$pkgdir"*.pkg.tar.*

    # 本地打包的源文件（由 package-files.sh 重新生成）
    rm -f "$pkgdir/files.tar.gz"

    # 下载的远程源码缓存（默认删除；--keep-cache 时保留）
    if [ "$KEEP_CACHE" -eq 0 ]; then
        rm -f "$pkgdir"*.tar.gz "$pkgdir"*.deb "$pkgdir"*.deb.part
    fi
done

msg "清理 out/ ..."
rm -rf out/pkgs out/repo out/rootfs out/sheng-repo.conf

msg "完成。"
