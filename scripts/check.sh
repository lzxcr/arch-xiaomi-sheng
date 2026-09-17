#!/usr/bin/env bash
# Fast repository consistency checks; no network or privileged operations.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# shellcheck source=scripts/lib/packages.sh
source "$SCRIPTS_DIR/lib/packages.sh"

FAILED=0

fail() {
  warn "$*"
  FAILED=1
}

check_shell_syntax() {
  local file
  local -a shell_files=()

  mapfile -t shell_files < <(
    {
      find "$SCRIPTS_DIR" -type f -name '*.sh' -print
      printf '%s\n' "$PROJECT_DIR/files/install/mkinitcpio-bootflash/bootflash"
      printf '%s\n' "$PROJECT_DIR/files/install/mkinitcpio-bootflash/sheng-fdt-identities"
      printf '%s\n' "$PROJECT_DIR/files/install/mkinitcpio-bootflash/sheng-boot-slot"
    } | sort -u
  )

  for file in "${shell_files[@]}"; do
    bash -n "$file" || fail "Shell 语法检查失败: ${file#"$PROJECT_DIR/"}"
  done

  if command -v shellcheck &>/dev/null; then
    shellcheck -x "${shell_files[@]}" || fail "ShellCheck 检查失败"
  else
    warn "未安装 shellcheck，仅执行 bash -n"
  fi
}

check_package_manifest() {
  local package_name dependency stage
  local -a actual_packages=()
  local -a manifest_packages=()
  local -a stage_packages=()
  declare -A seen=()

  mapfile -t actual_packages < <(
    find "$PKG_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
  )
  mapfile -t manifest_packages < <(printf '%s\n' "${PROJECT_PACKAGES[@]}" | sort)

  if ! diff -u \
      <(printf '%s\n' "${manifest_packages[@]}") \
      <(printf '%s\n' "${actual_packages[@]}") >/dev/null; then
    fail "scripts/lib/packages.sh 与 pkgs/*/PKGBUILD 不一致"
  fi

  for stage in "${BUILD_STAGES[@]}"; do
    read -r -a stage_packages <<< "${PACKAGES_BY_STAGE[$stage]}"
    for package_name in "${stage_packages[@]}"; do
      package_exists "$package_name" || fail "阶段 $stage 包含未知包: $package_name"
      [[ -z "${seen[$package_name]:-}" ]] || fail "包在多个阶段中重复: $package_name"
      seen["$package_name"]=1
    done
  done

  for package_name in "${PROJECT_PACKAGES[@]}"; do
    [[ -n "${seen[$package_name]:-}" ]] || fail "包未分配构建阶段: $package_name"
    # shellcheck disable=SC2086 # dependency list is intentionally word-split
    for dependency in ${PACKAGE_BUILD_DEPS[$package_name]:-}; do
      package_exists "$dependency" || fail "$package_name 依赖未知内部包: $dependency"
    done
  done
}

check_local_file_packages() {
  local package_name
  local -a package_names=()

  mapfile -t package_names < <(
    find "$PROJECT_DIR/files/direct" "$PROJECT_DIR/files/install" \
      -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -u
  )

  for package_name in "${package_names[@]}"; do
    [[ -f "$PKG_DIR/$package_name/PKGBUILD" ]] || {
      fail "本地文件没有对应 PKGBUILD: $package_name"
      continue
    }
    rg -q 'files\.tar\.gz' "$PKG_DIR/$package_name/PKGBUILD" || \
      fail "$package_name 有本地文件但 PKGBUILD 未引用 files.tar.gz"
  done
}

check_pkgbuild_metadata() {
  local index package_name
  local -a package_names=()
  local -a process_ids=()

  command -v makepkg &>/dev/null || {
    warn "未安装 makepkg，跳过 PKGBUILD 元数据检查"
    return
  }

  for package_name in "${PROJECT_PACKAGES[@]}"; do
    (
      cd "$PKG_DIR/$package_name"
      makepkg --printsrcinfo >/dev/null
    ) &
    process_ids+=("$!")
    package_names+=("$package_name")
  done

  for index in "${!process_ids[@]}"; do
    if ! wait "${process_ids[$index]}"; then
      fail "PKGBUILD 元数据无效: ${package_names[$index]}"
    fi
  done
}

main() {
  require_commands bash find rg sort
  check_shell_syntax
  check_package_manifest
  check_local_file_packages
  check_pkgbuild_metadata

  ((FAILED == 0)) || die "仓库检查失败"
  msg "仓库检查通过"
}

main
