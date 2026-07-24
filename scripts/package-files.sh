#!/usr/bin/env bash
#
# package-files.sh —— 将 files/{direct,install}/<pkg>/ 合并打包为 pkgs/<pkg>/files.tar.gz
#
# 用法: ./scripts/package-files.sh [--pkg PKG]
#
# 从 files/direct/<pkg>/ 和 files/install/<pkg>/ 收集文件，
# 合并为单一 files.tar.gz，供对应 pkgs/<pkg>/PKGBUILD 的 source=("files.tar.gz") 引用。
#
# 分类说明:
#   direct/   — 直接拷贝到根的文件（固件、二进制、ALSA UCM、传感器配置数据等）
#   install/  — 需要安装到系统特定位置的文件（systemd 单元、udev 规则、drop-in 等）
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

# ── 获取所有包名列表（union of direct/* + install/*）──────
get_all_pkgs() {
  local pkgs=()
  local seen=()

  # 扫描 direct/
  if [ -d "$FILES_DIR/direct" ]; then
    for dir in "$FILES_DIR/direct"/*/; do
      [ -d "$dir" ] || continue
      local pkg
      pkg="$(basename "$dir")"
      pkgs+=("$pkg")
      seen+=("$pkg")
    done
  fi

  # 扫描 install/，跳过已在 seen 中的
  if [ -d "$FILES_DIR/install" ]; then
    for dir in "$FILES_DIR/install"/*/; do
      [ -d "$dir" ] || continue
      local pkg
      pkg="$(basename "$dir")"
      local already=false
      for s in "${seen[@]}"; do
        [ "$s" = "$pkg" ] && { already=true; break; }
      done
      if [ "$already" = false ]; then
        pkgs+=("$pkg")
        seen+=("$pkg")
      fi
    done
  fi

  printf '%s\n' "${pkgs[@]}"
}

# ── 打包逻辑 ──────────────────────────────────────────────
package_dir() {
  local pkg="$1"
  local direct_dir="$FILES_DIR/direct/$pkg"
  local install_dir="$FILES_DIR/install/$pkg"
  local dst_dir="$PKG_DIR/$pkg"

  # 检查是否有可打包的文件
  local has_files=false

  if [ -d "$direct_dir" ]; then
    for entry in "$direct_dir"/*; do
      [ -e "$entry" ] || continue
      local name
      name="$(basename "$entry")"
      if [ "$name" != "preprocess.sh" ]; then
        has_files=true
        break
      fi
    done
  fi

  if [ "$has_files" = false ] && [ -d "$install_dir" ]; then
    for entry in "$install_dir"/*; do
      [ -e "$entry" ] || continue
      local name
      name="$(basename "$entry")"
      if [ "$name" != "preprocess.sh" ]; then
        has_files=true
        break
      fi
    done
  fi

  if [ "$has_files" = false ]; then
    warn "跳过 $pkg：files/{direct,install}/$pkg 中均无可打包文件"
    return 0
  fi

  mkdir -p "$dst_dir"
  local tar_file="$dst_dir/files.tar.gz"

  msg "打包 $pkg → $tar_file ..."

  # 使用临时目录合并 direct/ + install/ 的内容
  local tmpdir
  tmpdir="$(mktemp -d)"

  if [ -d "$direct_dir" ]; then
    cp -a "$direct_dir"/* "$tmpdir/" 2>/dev/null || true
  fi

  if [ -d "$install_dir" ]; then
    cp -a "$install_dir"/* "$tmpdir/" 2>/dev/null || true
  fi

  # 打包（排除 preprocess.sh）
  tar czf "$tar_file" \
    --exclude='preprocess.sh' \
    -C "$tmpdir" \
    .

  rm -rf "$tmpdir"

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
    local direct_ok=false install_ok=false
    [ -d "$FILES_DIR/direct/$FILTER_PKG" ] && direct_ok=true
    [ -d "$FILES_DIR/install/$FILTER_PKG" ] && install_ok=true
    if [ "$direct_ok" = false ] && [ "$install_ok" = false ]; then
      error "目录不存在: files/{direct,install}/$FILTER_PKG"
      exit 1
    fi
    package_dir "$FILTER_PKG"
  else
    # 获取所有包
    local pkgs
    mapfile -t pkgs < <(get_all_pkgs)

    if [ ${#pkgs[@]} -eq 0 ]; then
      warn "files/{direct,install}/ 下没有找到任何包"
      exit 0
    fi

    local count=0
    for pkg in "${pkgs[@]}"; do
      package_dir "$pkg"
      count=$((count + 1))
    done
    msg "完成：已处理 $count 个包"
  fi
}

main "$@"
