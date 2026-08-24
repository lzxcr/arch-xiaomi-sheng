#!/usr/bin/env bash
# Build the project packages in dependency-safe stages using a clean chroot.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# shellcheck source=scripts/lib/packages.sh
source "$SCRIPTS_DIR/lib/packages.sh"

STAGE_FILTER=""
FROM_PACKAGE=""
SKIP_PACKAGES=""
LIST_ONLY=0

usage() {
  cat <<'EOF'
用法: build-pkgs.sh [选项]

选项:
  --stage N          仅构建阶段 N（0..3）
  --tier N           --stage 的兼容别名
  --from PKG         从指定包继续构建，保留已有依赖产物
  --skip A,B         跳过逗号分隔的包
  --list             打印本次选择的包，不执行构建
  -h, --help         显示帮助
EOF
}

while (($# > 0)); do
  case "$1" in
    --stage|--tier)
      require_option_value "$1" "${2:-}"
      STAGE_FILTER="$2"
      shift 2
      ;;
    --from)
      require_option_value "$1" "${2:-}"
      FROM_PACKAGE="$2"
      shift 2
      ;;
    --skip)
      require_option_value "$1" "${2:-}"
      SKIP_PACKAGES="$2"
      shift 2
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "未知参数: $1（使用 --help 查看帮助）"
      ;;
  esac
done

[[ -z "$STAGE_FILTER" || -z "$FROM_PACKAGE" ]] || \
  die "--stage/--tier 不能与 --from 同时使用"

if [[ -n "$STAGE_FILTER" ]]; then
  [[ "$STAGE_FILTER" =~ ^[0-3]$ ]] || die "无效阶段: $STAGE_FILTER（可选 0..3）"
fi

if [[ -n "$FROM_PACKAGE" ]]; then
  package_exists "$FROM_PACKAGE" || die "未知包: $FROM_PACKAGE"
fi

declare -A SKIPPED=()
if [[ -n "$SKIP_PACKAGES" ]]; then
  IFS=',' read -r -a skip_list <<< "$SKIP_PACKAGES"
  for package_name in "${skip_list[@]}"; do
    [[ -n "$package_name" ]] || die "--skip 包含空包名"
    package_exists "$package_name" || die "--skip 中的包不存在: $package_name"
    SKIPPED["$package_name"]=1
  done
fi

selected_packages() {
  local package_name
  local started=0

  [[ -z "$FROM_PACKAGE" ]] && started=1

  for package_name in "${PROJECT_PACKAGES[@]}"; do
    if [[ -n "$STAGE_FILTER" ]]; then
      [[ " ${PACKAGES_BY_STAGE[$STAGE_FILTER]} " == *" $package_name "* ]] || continue
    fi

    if ((started == 0)); then
      [[ "$package_name" == "$FROM_PACKAGE" ]] || continue
      started=1
    fi

    [[ -z "${SKIPPED[$package_name]:-}" ]] || continue
    printf '%s\n' "$package_name"
  done
}

mapfile -t SELECTED_PACKAGES < <(selected_packages)
((${#SELECTED_PACKAGES[@]} > 0)) || die "参数过滤后没有需要构建的包"

if ((LIST_ONLY)); then
  printf '%s\n' "${SELECTED_PACKAGES[@]}"
  exit 0
fi

find_dependency_package() {
  local dependency="$1"
  local -a candidates=()

  mapfile -t candidates < <(
    find "$OUT_PKGS_DIR" -maxdepth 1 -type f \
      -name "${dependency}-*.pkg.tar.*" -print | sort -V
  )
  ((${#candidates[@]} > 0)) || return 1
  printf '%s\n' "${candidates[-1]}"
}

init_chroot() {
  if [[ ! -d "$BUILD_CHROOT/root" ]]; then
    msg "初始化 clean chroot: $BUILD_CHROOT"
    mkarchroot "$BUILD_CHROOT/root" base-devel
  else
    msg "使用已有 clean chroot: $BUILD_CHROOT"
  fi
}

prepare_local_archives() {
  local package_name

  for package_name in "${SELECTED_PACKAGES[@]}"; do
    if [[ -d "$PROJECT_DIR/files/direct/$package_name" || \
          -d "$PROJECT_DIR/files/install/$package_name" ]]; then
      "$SCRIPTS_DIR/package-files.sh" --pkg "$package_name"
    fi
  done
}

build_package() {
  local package_name="$1"
  local package_dir="$PKG_DIR/$package_name"
  local dependency dependency_package
  local -a install_args=()
  local -a artifacts=()

  [[ -f "$package_dir/PKGBUILD" ]] || die "PKGBUILD 不存在: $package_dir/PKGBUILD"

  # shellcheck disable=SC2086 # dependency list is intentionally word-split
  for dependency in ${PACKAGE_BUILD_DEPS[$package_name]:-}; do
    dependency_package="$(find_dependency_package "$dependency")" || \
      die "缺少 $package_name 的内部依赖包 $dependency；请先构建依赖阶段"
    install_args+=(-I "$dependency_package")
  done

  msg "构建 $package_name"
  (
    cd "$package_dir"
    makechrootpkg -c -r "$BUILD_CHROOT" \
      "${install_args[@]}" \
      -- --syncdeps --noconfirm --cleanbuild
  )

  mapfile -t artifacts < <(
    find "$package_dir" -maxdepth 1 -type f -name '*.pkg.tar.*' -print | sort
  )
  ((${#artifacts[@]} > 0)) || die "$package_name 构建成功但未找到包产物"

  # Replace only this package after a successful build. Failed or filtered
  # builds keep previously built dependencies available for --from/--stage.
  find "$OUT_PKGS_DIR" -maxdepth 1 -type f \
    -name "${package_name}-*.pkg.tar.*" -delete
  mv -- "${artifacts[@]}" "$OUT_PKGS_DIR/"
  msg "完成 $package_name"
}

main() {
  require_commands mkarchroot makechrootpkg pacman

  msg "生成所选包的本地 files.tar.gz"
  prepare_local_archives

  mkdir -p "$OUT_PKGS_DIR"
  init_chroot

  local package_name
  local stage
  local stage_has_packages

  for stage in "${BUILD_STAGES[@]}"; do
    stage_has_packages=0
    for package_name in "${SELECTED_PACKAGES[@]}"; do
      if [[ " ${PACKAGES_BY_STAGE[$stage]} " == *" $package_name "* ]]; then
        stage_has_packages=1
        break
      fi
    done
    ((stage_has_packages)) || continue

    msg "阶段 $stage: ${PACKAGES_BY_STAGE[$stage]}"
    for package_name in "${SELECTED_PACKAGES[@]}"; do
      [[ " ${PACKAGES_BY_STAGE[$stage]} " == *" $package_name "* ]] || continue
      build_package "$package_name"
    done
  done

  msg "构建完成，产物位于 $OUT_PKGS_DIR"
}

main
