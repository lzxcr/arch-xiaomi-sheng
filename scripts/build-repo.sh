#!/usr/bin/env bash
#
# build-repo.sh —— 将 out/pkgs/*.pkg.tar.* 注册为本地 pacman 仓库
#
# 用法: ./scripts/build-repo.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=scripts/config.sh
source "$SCRIPT_DIR/config.sh"

msg()  { echo -e "\033[1;34m==>\033[0m $*"; }
error(){ echo -e "\033[1;31m!!>\033[0m $*" >&2; }

main() {
  mkdir -p "$OUT_REPO_DIR"

  local pkg_count
  pkg_count=$(find "$OUT_PKGS_DIR" -name '*.pkg.tar.*' -type f | wc -l)

  if [ "$pkg_count" -eq 0 ]; then
    error "没有找到已构建的包在 $OUT_PKGS_DIR"
    error "请先执行 ./scripts/build-pkgs.sh"
    exit 1
  fi

  msg "复制 $pkg_count 个包到仓库目录 ..."
  cp "$OUT_PKGS_DIR"/*.pkg.tar.* "$OUT_REPO_DIR/"

  msg "创建仓库数据库: $OUT_REPO_DIR/sheng.db.tar.gz ..."
  repo-add "$OUT_REPO_DIR/sheng.db.tar.gz" "$OUT_REPO_DIR"/*.pkg.tar.*

  local repo_conf="$OUT_DIR/sheng-repo.conf"
  cat > "$repo_conf" <<-EOF
# sheng 本地仓库 — 由 build-repo.sh 自动生成
# 追加到 /etc/pacman.conf 使用
[sheng]
SigLevel = Never
Server = file://$(readlink -f "$OUT_REPO_DIR")
EOF

  msg "══════ 仓库构建完成 ══════"
  echo "仓库目录: $OUT_REPO_DIR"
  echo "仓库配置: $repo_conf"
  echo ""
  echo "在 rootfs 中使用本仓库:"
  echo "  cat $repo_conf >> /mnt/etc/pacman.conf"
  echo "  或使用 mkrootfs.sh 自动完成"
}

main "$@"
