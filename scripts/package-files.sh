#!/usr/bin/env bash
# Create deterministic files.tar.gz archives from repository-managed files.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

readonly FILES_DIR="$PROJECT_DIR/files"
FILTER_PACKAGE=""

usage() {
  cat <<'EOF'
用法: package-files.sh [--pkg PKG]

不指定 --pkg 时，处理 files/direct 与 files/install 下的全部包。
EOF
}

while (($# > 0)); do
  case "$1" in
    --pkg)
      require_option_value "$1" "${2:-}"
      FILTER_PACKAGE="$2"
      shift 2
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

has_package_files() {
  local source_dir="$1"
  [[ -d "$source_dir" ]] || return 1
  find "$source_dir" -mindepth 1 ! -name preprocess.sh -print -quit | grep -q .
}

package_files() (
  local package_name="$1"
  local direct_dir="$FILES_DIR/direct/$package_name"
  local install_dir="$FILES_DIR/install/$package_name"
  local package_dir="$PKG_DIR/$package_name"
  local archive="$package_dir/files.tar.gz"
  local temporary_dir
  local entry_count archive_size

  [[ -f "$package_dir/PKGBUILD" ]] || die "缺少 $package_name/PKGBUILD"

  if ! has_package_files "$direct_dir" && ! has_package_files "$install_dir"; then
    warn "跳过 $package_name：没有本地文件"
    exit 0
  fi

  temporary_dir="$(mktemp -d)"
  trap 'rm -rf "$temporary_dir"' EXIT

  [[ ! -d "$direct_dir" ]] || cp -a "$direct_dir/." "$temporary_dir/"
  [[ ! -d "$install_dir" ]] || cp -a "$install_dir/." "$temporary_dir/"

  mkdir -p "$package_dir"
  tar \
    --sort=name \
    --mtime="@${SOURCE_DATE_EPOCH:-0}" \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --exclude=preprocess.sh \
    -czf "$archive" \
    -C "$temporary_dir" .

  entry_count="$(tar -tzf "$archive" | wc -l)"
  archive_size="$(du -h "$archive" | cut -f1)"
  msg "$package_name: $entry_count 个归档条目，$archive_size"
)

all_file_packages() {
  local -a roots=()
  [[ ! -d "$FILES_DIR/direct" ]] || roots+=("$FILES_DIR/direct")
  [[ ! -d "$FILES_DIR/install" ]] || roots+=("$FILES_DIR/install")
  ((${#roots[@]} > 0)) || return 0

  find "${roots[@]}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -u
}

main() {
  local -a package_names=()
  local package_name

  require_commands tar

  if [[ -n "$FILTER_PACKAGE" ]]; then
    if [[ ! -d "$FILES_DIR/direct/$FILTER_PACKAGE" && \
          ! -d "$FILES_DIR/install/$FILTER_PACKAGE" ]]; then
      die "目录不存在: files/{direct,install}/$FILTER_PACKAGE"
    fi
    package_names=("$FILTER_PACKAGE")
  else
    mapfile -t package_names < <(all_file_packages)
  fi

  ((${#package_names[@]} > 0)) || die "files/ 下没有可打包的包"

  for package_name in "${package_names[@]}"; do
    package_files "$package_name"
  done
}

main
