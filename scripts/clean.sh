#!/usr/bin/env bash
#
# clean.sh —— 清理所有构建产物，保持工作区干净
# 用法: ./scripts/clean.sh [--keep-cache]
#   --keep-cache: 保留已下载的源码缓存（*.tar.gz, *.deb, git clones）
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

KEEP_CACHE=0
[[ "${1:-}" = "--keep-cache" ]] && KEEP_CACHE=1

cd "$PROJECT_DIR"

echo "==> 清理 pkgs/*/ 下构建产物 ..."

for pkgdir in pkgs/*/; do
    [ -d "$pkgdir/src" ] && rm -rf "$pkgdir/src" && echo "  rm -rf ${pkgdir}src"
    [ -d "$pkgdir/pkg" ] && rm -rf "$pkgdir/pkg" && echo "  rm -rf ${pkgdir}pkg"
    
    # 删除 .pkg.tar.*（包文件）
    for f in "$pkgdir"*.pkg.tar.*; do
        [ -f "$f" ] && rm -f "$f" && echo "  rm $f"
    done
    
    # 删除 files.tar.gz（由 package-files.sh 重新生成）
    [ -f "$pkgdir/files.tar.gz" ] && rm -f "$pkgdir/files.tar.gz" && echo "  rm ${pkgdir}files.tar.gz"
done

echo "==> 清理 out/ ..."
rm -rf out/pkgs out/repo out/rootfs out/sheng-repo.conf 2>/dev/null
echo "  rm -rf out/*"

echo "==> 完成。"
