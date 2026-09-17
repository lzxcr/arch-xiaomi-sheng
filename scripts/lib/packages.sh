#!/usr/bin/env bash
# shellcheck disable=SC2034
# Canonical package manifest. Build and rootfs scripts both consume this file.

readonly BUILD_STAGES=(0 1 2 3)

declare -Ar PACKAGES_BY_STAGE=(
  [0]="hexagonrpc libksysguard libssc linux-firmware-sheng linux-xiaomi-sheng"
  [1]="iio-sensor-proxy ksystemstats"
  [2]="xiaomi-sheng-rfsa xiaomi-sheng-sensors"
  [3]="alsa-ucm-xiaomi-sheng xiaomi-charger-mode mkinitcpio-bootflash xiaomi-sheng-devauth xiaomi-mipps-auth xiaomi-pen-status xiaomi-sheng-fingerprint xiaomi-sheng-keyboard-helper xiaomi-sheng-thp"
)

# Internal packages that must be injected into the clean chroot before build.
declare -Ar PACKAGE_BUILD_DEPS=(
  [iio-sensor-proxy]="libssc"
  [ksystemstats]="libksysguard"
  [xiaomi-sheng-sensors]="hexagonrpc libssc iio-sensor-proxy"
  [xiaomi-sheng-rfsa]="hexagonrpc"
  [xiaomi-sheng-keyboard-helper]="libssc"
  [xiaomi-sheng-thp]="libssc"
)

declare -a PROJECT_PACKAGES=()
declare -a ROOTFS_PACKAGES=()
for _stage in "${BUILD_STAGES[@]}"; do
  read -r -a _stage_packages <<< "${PACKAGES_BY_STAGE[$_stage]}"
  PROJECT_PACKAGES+=("${_stage_packages[@]}")
  for _package in "${_stage_packages[@]}"; do
    case "$_package" in
      ksystemstats|libksysguard) ;;
      *) ROOTFS_PACKAGES+=("$_package") ;;
    esac
  done
done
readonly PROJECT_PACKAGES ROOTFS_PACKAGES
unset _package _stage _stage_packages

package_exists() {
  local wanted="$1"
  local package_name

  for package_name in "${PROJECT_PACKAGES[@]}"; do
    [[ "$package_name" == "$wanted" ]] && return 0
  done
  return 1
}
