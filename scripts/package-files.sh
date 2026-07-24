#!/usr/bin/env bash
#
# package-files.sh —— 将 files/<pkg>/ 打包为 pkgs/<pkg>/files.tar.gz
#
# 用法: ./scripts/package-files.sh [--pkg PKG]
#
# 每个 files/<pkg>/ 下的文件（不含 preprocess.sh）被打包，
# 供对应 pkgs/<pkg>/PKGBUILD 的 source=("files.tar.gz") 引用。
#
# 设计文档: docs/files-restructure.md
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/config.sh
source "$SCRIPT_DIR/config.sh"

FILES_DIR="$PROJECT_DIR/files"
PKG_DIR="$PROJECT_DIR/pkgs"

# ── 参数解析 ──────────────────────────────────────────────
FILTER_PKG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pkg) FILTER_PKG="$2"; shift 2 ;;
    --help) echo "用法: $0 [--pkg <包名>]"; exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

# ── 辅助函数 ──────────────────────────────────────────────
msg()   { echo -e "\033[1;34m==>\033[0m $*"; }
warn()  { echo -e "\033[1;33m!>\033[0m $*" >&2; }
error() { echo -e "\033[1;31m!!>\033[0m $*" >&2; }

# ── 打包逻辑 ──────────────────────────────────────────────
package_dir() {
  local pkg="$1"
  local src_dir="$FILES_DIR/$pkg"
  local dst_dir="$PKG_DIR/$pkg"

  # 检查源目录是否有可打包的文件（排除 preprocess.sh）
  local has_files=false
  for entry in "$src_dir"/*; do
    local name
    name="$(basename "$entry")"
    if [ "$name" != "preprocess.sh" ]; then
      has_files=true
      break
    fi
  done

  if [ "$has_files" = false ]; then
    warn "跳过 $pkg：$src_dir 中无可打包文件"
    return 0
  fi

  mkdir -p "$dst_dir"

  # 构建排除 preprocess.sh 的打包命令
  # 使用 --exclude 排除 preprocess.sh，同时保留目录结构
  local tar_file="$dst_dir/files.tar.gz"

  msg "打包 $pkg → $tar_file ..."
  tar czf "$tar_file" \
    --exclude='preprocess.sh' \
    -C "$src_dir" \
    .

  local file_count
  file_count=$(tar tzf "$tar_file" | wc -l)
  local size
  size=$(du -h "$tar_file" | cut -f1)
  msg "  ✓ $pkg: $file_count 个文件, $size"
}

# ── 主逻辑 ──────────────────────────────────────────────
main() {
  if [ -n "$FILTER_PKG" ]; then
    # 仅打包指定包
    if [ ! -d "$FILES_DIR/$FILTER_PKG" ]; then
      error "目录不存在: $FILES_DIR/$FILTER_PKG"
      exit 1
    fi
    package_dir "$FILTER_PKG"
  else
    # 遍历 files/ 下所有子目录
    local count=0
    for dir in "$FILES_DIR"/*/; do
      [ -d "$dir" ] || continue
      local pkg
      pkg="$(basename "$dir")"
      package_dir "$pkg"
      count=$((count + 1))
    done
    msg "完成：已处理 $count 个包"
  fi
}

main "$@"
