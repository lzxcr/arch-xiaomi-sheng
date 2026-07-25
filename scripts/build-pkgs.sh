#!/usr/bin/env bash
#
# build-pkgs.sh —— 按拓扑依赖序在 clean chroot 中构建所有包
#
# 用法: ./scripts/build-pkgs.sh [--tier N] [--from PKG] [--skip PKG1,PKG2]
#
# 依赖拓扑:
#   Tier 0: hexagonrpc libssc linux-firmware-sheng linux-xiaomi-sheng
#   Tier 1: iio-sensor-proxy (depends: libssc)
#   Tier 2: xiaomi-sheng-sensors (depends: iio-sensor-proxy)
#   Tier 3: alsa-ucm-xiaomi-sheng xiaomi-charger-mode mkinitcpio-bootflash
#           xiaomi-sheng-devauth xiaomi-mipps-auth xiaomi-pen-status
#           xiaomi-sheng-fingerprint xiaomi-sheng-keyboard-helper xiaomi-sheng-thp
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/config.sh
source "$SCRIPT_DIR/config.sh"

# ── 拓扑定义 ──────────────────────────────────────────────
declare -A PKG_TIERS
PKG_TIERS[0]="hexagonrpc libssc linux-firmware-sheng linux-xiaomi-sheng"
PKG_TIERS[1]="iio-sensor-proxy"
PKG_TIERS[2]="xiaomi-sheng-sensors"
PKG_TIERS[3]="alsa-ucm-xiaomi-sheng xiaomi-charger-mode mkinitcpio-bootflash xiaomi-sheng-devauth xiaomi-mipps-auth xiaomi-pen-status xiaomi-sheng-fingerprint xiaomi-sheng-keyboard-helper xiaomi-sheng-thp"

ALL_PKGS=""
for t in 0 1 2 3; do ALL_PKGS="$ALL_PKGS ${PKG_TIERS[$t]}"; done

# 依赖声明（用于 -I 安装顺序）
declare -A PKG_DEPS
PKG_DEPS[iio-sensor-proxy]="libssc"
PKG_DEPS[xiaomi-sheng-sensors]="iio-sensor-proxy"
# 其余包无内部跨包依赖

# ── 参数解析 ──────────────────────────────────────────────
TIER_FILTER=""
FROM_PKG=""
SKIP_PKGS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier)    TIER_FILTER="$2"; shift 2 ;;
    --from)    FROM_PKG="$2";    shift 2 ;;
    --skip)    SKIP_PKGS="$2";   shift 2 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

# ── 辅助函数 ──────────────────────────────────────────────

msg()   { echo -e "\033[1;34m==>\033[0m $*"; }
error() { echo -e "\033[1;31m!!>\033[0m $*" >&2; }

should_build() {
  local pkg="$1"
  if [ -n "$TIER_FILTER" ]; then
    local found=0
    for p in ${PKG_TIERS[$TIER_FILTER]}; do
      [ "$p" = "$pkg" ] && found=1 && break
    done
    [ "$found" -eq 0 ] && return 1
  fi
  if [ -n "$FROM_PKG" ]; then
    local started=0
    for p in $ALL_PKGS; do
      [ "$p" = "$FROM_PKG" ] && started=1
      if [ "$started" -eq 0 ]; then continue; fi
      [ "$p" = "$pkg" ] && break
    done
    [ "$started" -eq 0 ] && return 1
  fi
  if [ -n "$SKIP_PKGS" ]; then
    IFS=',' read -ra skip_arr <<< "$SKIP_PKGS"
    for s in "${skip_arr[@]}"; do
      [ "$s" = "$pkg" ] && return 1
    done
  fi
  return 0
}

check_prereqs() {
  local missing=0
  for cmd in mkarchroot makechrootpkg pacman; do
    if ! command -v "$cmd" &>/dev/null; then
      error "缺少命令: $cmd（请安装 arch-install-scripts 和 devtools）"
      missing=1
    fi
  done
  [ "$missing" -eq 1 ] && exit 1
}

init_chroot() {
  if [ ! -d "$BUILD_CHROOT/root" ]; then
    msg "初始化 clean chroot: $BUILD_CHROOT ..."
    mkarchroot "$BUILD_CHROOT/root" base-devel
  else
    msg "使用已有 clean chroot: $BUILD_CHROOT"
  fi
}

main() {
  # 清理旧构建产物 + 重新打包本地源文件
  msg "预处理: 清理构建产物 ..."
  "$SCRIPT_DIR/clean.sh" --keep-cache
  msg "预处理: 打包 files/ → files.tar.gz ..."
  "$SCRIPT_DIR/package-files.sh"

  mkdir -p "$OUT_PKGS_DIR"
  check_prereqs
  init_chroot

  for tier in 0 1 2 3; do
    local pkgs_list="${PKG_TIERS[$tier]}"
    [ -z "$pkgs_list" ] && continue
    msg "══════ Tier $tier: $pkgs_list ══════"

    for pkg in $pkgs_list; do
      should_build "$pkg" || { msg "  跳过 $pkg（参数过滤）"; continue; }

      local pkgdir="$PKG_DIR/$pkg"
      if [ ! -f "$pkgdir/PKGBUILD" ]; then
        error "PKGBUILD 不存在: $pkgdir/PKGBUILD"
        exit 1
      fi

      msg "构建 $pkg ..."

      local install_args=()
      local dep_list="${PKG_DEPS[$pkg]:-}"
      if [ -n "$dep_list" ]; then
        for dep in $dep_list; do
          local dep_pkg
          dep_pkg=$(find "$OUT_PKGS_DIR" -name "${dep}-*.pkg.tar.*" | head -1)
          if [ -n "$dep_pkg" ]; then
            install_args+=(-I "$dep_pkg")
          else
            error "缺少依赖包: $dep（未在 $OUT_PKGS_DIR 中找到）"
            exit 1
          fi
        done
      fi

      (cd "$pkgdir" && makechrootpkg -c -r "$BUILD_CHROOT" \
        "${install_args[@]}" \
        -- --syncdeps --noconfirm --skippgpcheck)

      msg "收集 $pkg 构建产物 ..."
      find "$pkgdir" -maxdepth 1 -name '*.pkg.tar.*' -exec mv {} "$OUT_PKGS_DIR/" \;
      (cd "$pkgdir" && rm -f *.pkg.tar.*)

      msg "✓ $pkg 构建完成"
    done
  done

  msg "══════ 全部构建完成 ══════"
  echo "产物目录: $OUT_PKGS_DIR"
  ls -1 "$OUT_PKGS_DIR"/*.pkg.tar.* 2>/dev/null || echo "(无包产物)"
}

main "$@"