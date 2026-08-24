#!/usr/bin/env bash
# Assemble a flashable Arch Linux ARM rootfs and Android boot image.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# shellcheck source=scripts/lib/packages.sh
source "$SCRIPTS_DIR/lib/packages.sh"

MOUNT_DIR=""

usage() {
  cat <<'EOF'
用法: mkrootfs.sh [选项]

选项:
  --desktop none|kde|gnome
  --extra "PKG ..."
  --hostname NAME
  --user NAME
  --password PASSWORD
  --size MIB
  --partlabel LABEL
  --cmdline "KERNEL COMMAND LINE"
  -h, --help
EOF
}

while (($# > 0)); do
  case "$1" in
    --desktop)
      require_option_value "$1" "${2:-}"
      ROOTFS_DESKTOP="$2"
      shift 2
      ;;
    --extra)
      require_option_value "$1" "${2:-}"
      ROOTFS_EXTRA_PKGS="$2"
      shift 2
      ;;
    --hostname)
      require_option_value "$1" "${2:-}"
      ROOTFS_HOSTNAME="$2"
      shift 2
      ;;
    --user)
      require_option_value "$1" "${2:-}"
      ROOTFS_USER="$2"
      shift 2
      ;;
    --password)
      require_option_value "$1" "${2:-}"
      ROOTFS_PASSWORD="$2"
      shift 2
      ;;
    --size)
      require_option_value "$1" "${2:-}"
      ROOTFS_SIZE_MB="$2"
      shift 2
      ;;
    --partlabel)
      require_option_value "$1" "${2:-}"
      ROOTFS_PARTLABEL="$2"
      ROOTFS_KERNEL_CMDLINE="root=PARTLABEL=${ROOTFS_PARTLABEL} rw rootwait"
      shift 2
      ;;
    --cmdline)
      require_option_value "$1" "${2:-}"
      ROOTFS_KERNEL_CMDLINE="$2"
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

cleanup() {
  if [[ -n "$MOUNT_DIR" ]] && mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
    warn "清理挂载点: $MOUNT_DIR"
    sudo umount -R "$MOUNT_DIR" || true
  fi
  [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]] || rmdir "$MOUNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT

desktop_packages() {
  case "$ROOTFS_DESKTOP" in
    kde)
      printf '%s\n' plasma-meta konsole dolphin plasma-nm plasma-pa \
        kscreen powerdevil spectacle gwenview sddm
      ;;
    gnome)
      printf '%s\n' gnome gnome-tweaks gdm networkmanager
      ;;
    none)
      ;;
    *)
      die "不支持的桌面: $ROOTFS_DESKTOP（可选 none、kde、gnome）"
      ;;
  esac
}

validate_options() {
  [[ "$ROOTFS_SIZE_MB" =~ ^[0-9]+$ ]] || die "--size 必须是整数 MiB"
  ((ROOTFS_SIZE_MB >= 2048)) || die "rootfs 镜像至少需要 2048 MiB"
  [[ "$ROOTFS_HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || die "主机名格式无效"
  [[ -z "$ROOTFS_USER" || "$ROOTFS_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "用户名格式无效"
  [[ "$ROOTFS_PARTLABEL" =~ ^[a-zA-Z0-9._-]+$ ]] || die "分区标签格式无效"
  desktop_packages >/dev/null
}

verify_filesystem() {
  local image="$1"
  local status

  set +e
  e2fsck -fp "$image"
  status=$?
  set -e
  ((status <= 1)) || die "文件系统检查失败，e2fsck 状态码: $status"
}

main() {
  local rootfs_image="$OUT_ROOTFS_DIR/rootfs.img"
  local boot_image="$OUT_ROOTFS_DIR/boot.img"
  local repository_in_rootfs
  local -a desktop_pkgs=()
  local -a extra_pkgs=()
  local -a repository_files=()
  local -a base_pkgs=(base vim sudo networkmanager)

  validate_options
  require_commands arch-chroot awk chpasswd cp e2fsck find install mkfs.ext4 \
    mount mountpoint pacstrap sed sudo tee truncate umount

  [[ -d "$OUT_REPO_DIR" ]] || die "本地仓库不存在；请先运行 make repo"
  mapfile -t repository_files < <(
    find "$OUT_REPO_DIR" -maxdepth 1 \( -type f -o -type l \) -print | sort
  )
  ((${#repository_files[@]} > 0)) || die "本地仓库为空: $OUT_REPO_DIR"
  [[ -e "$OUT_REPO_DIR/sheng.db" ]] || die "仓库数据库缺失: $OUT_REPO_DIR/sheng.db"

  mkdir -p "$OUT_ROOTFS_DIR"
  rm -f "$boot_image"
  truncate -s 0 "$rootfs_image"
  truncate -s "${ROOTFS_SIZE_MB}M" "$rootfs_image"
  mkfs.ext4 -F -L sheng-root "$rootfs_image"

  MOUNT_DIR="$(mktemp -d)"
  msg "挂载 rootfs: $MOUNT_DIR"
  sudo mount -o loop "$rootfs_image" "$MOUNT_DIR"

  # Do not install the generic kernel/firmware: project packages provide the
  # device-specific replacements and would otherwise conflict in pacman.
  msg "安装 Arch Linux ARM 基础系统"
  sudo pacstrap -K "$MOUNT_DIR" "${base_pkgs[@]}"

  repository_in_rootfs="$MOUNT_DIR/opt/sheng-repo"
  sudo install -d -m 0755 "$repository_in_rootfs"
  sudo cp -a -- "${repository_files[@]}" "$repository_in_rootfs/"
  # Insert sheng before the distribution repositories. Several project
  # packages intentionally override packages with the same official name
  # (notably iio-sensor-proxy), and pacman resolves ties by repository order.
  awk '
    function print_sheng() {
      print ""
      print "[sheng]"
      print "SigLevel = Never"
      print "Server = file:///opt/sheng-repo"
    }
    !inserted && /^\[[^]]+\]$/ && $0 != "[options]" {
      print_sheng()
      inserted = 1
    }
    { print }
    END {
      if (!inserted) print_sheng()
    }
  ' "$MOUNT_DIR/etc/pacman.conf" | \
    sudo tee "$MOUNT_DIR/etc/pacman.conf.new" >/dev/null
  sudo mv "$MOUNT_DIR/etc/pacman.conf.new" "$MOUNT_DIR/etc/pacman.conf"

  msg "安装 ${#PROJECT_PACKAGES[@]} 个 sheng 硬件支持包"
  # Suppress post hooks during the package transaction. The boot entry does
  # not exist yet, and running a flashing hook from a mounted build image is
  # unsafe. A final, explicitly non-flashing mkinitcpio run happens below.
  sudo arch-chroot "$MOUNT_DIR" /usr/bin/env MKINITCPIO_POST_HOOKS=/dev/null \
    pacman -Syu --noconfirm -- "${PROJECT_PACKAGES[@]}"

  mapfile -t desktop_pkgs < <(desktop_packages)
  if ((${#desktop_pkgs[@]} > 0)); then
    msg "安装桌面环境: $ROOTFS_DESKTOP"
    sudo arch-chroot "$MOUNT_DIR" pacman -S --needed --noconfirm -- "${desktop_pkgs[@]}"
  fi

  if [[ -n "$ROOTFS_EXTRA_PKGS" ]]; then
    read -r -a extra_pkgs <<< "$ROOTFS_EXTRA_PKGS"
    msg "安装额外包: ${extra_pkgs[*]}"
    sudo arch-chroot "$MOUNT_DIR" pacman -S --needed --noconfirm -- "${extra_pkgs[@]}"
  fi

  msg "配置系统"
  printf '%s\n' "$ROOTFS_HOSTNAME" | sudo tee "$MOUNT_DIR/etc/hostname" >/dev/null
  cat <<EOF | sudo tee "$MOUNT_DIR/etc/hosts" >/dev/null
127.0.0.1   localhost
127.0.1.1   $ROOTFS_HOSTNAME.localdomain $ROOTFS_HOSTNAME
::1         localhost ip6-localhost ip6-loopback
EOF

  sudo sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' "$MOUNT_DIR/etc/locale.gen"
  sudo arch-chroot "$MOUNT_DIR" locale-gen
  printf 'LANG=en_US.UTF-8\n' | sudo tee "$MOUNT_DIR/etc/locale.conf" >/dev/null

  printf 'root:%s\n' "$ROOTFS_PASSWORD" | sudo chpasswd -R "$MOUNT_DIR"
  if [[ -n "$ROOTFS_USER" ]]; then
    sudo arch-chroot "$MOUNT_DIR" useradd -m -G wheel -s /bin/bash "$ROOTFS_USER"
    printf '%s:%s\n' "$ROOTFS_USER" "$ROOTFS_PASSWORD" | sudo chpasswd -R "$MOUNT_DIR"
  fi

  sudo sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' \
    "$MOUNT_DIR/etc/sudoers"
  sudo arch-chroot "$MOUNT_DIR" systemctl enable NetworkManager

  case "$ROOTFS_DESKTOP" in
    gnome) sudo arch-chroot "$MOUNT_DIR" systemctl enable gdm ;;
    kde) sudo arch-chroot "$MOUNT_DIR" systemctl enable sddm ;;
  esac

  sudo install -d -m 0755 "$MOUNT_DIR/boot/loader/entries"
  cat <<EOF | sudo tee "$MOUNT_DIR/boot/loader/entries/arch.conf" >/dev/null
title Arch Linux (Xiaomi sheng)
linux /Image
initrd /initramfs-sheng.img
devicetree /sm8550-xiaomi-sheng.dtb
options $ROOTFS_KERNEL_CMDLINE
EOF

  msg "生成 initramfs 与 boot.img（构建环境禁止刷写分区）"
  sudo arch-chroot "$MOUNT_DIR" /usr/bin/env BOOTFLASH_NO_FLASH=1 \
    mkinitcpio -p linux-xiaomi-sheng
  [[ -f "$MOUNT_DIR/boot/boot.img" ]] || die "boot.img 未生成"
  sudo cp "$MOUNT_DIR/boot/boot.img" "$boot_image"
  sudo chown "$(id -u):$(id -g)" "$boot_image"

  sudo arch-chroot "$MOUNT_DIR" pacman -Scc --noconfirm || true

  msg "卸载并检查文件系统"
  sudo umount -R "$MOUNT_DIR"
  verify_filesystem "$rootfs_image"

  msg "rootfs 已生成: $rootfs_image"
  msg "boot 镜像已生成: $boot_image"
  printf '刷写示例:\n'
  printf '  fastboot flash %s %s\n' "$ROOTFS_PARTLABEL" "$rootfs_image"
  printf '  fastboot flash boot_b %s\n' "$boot_image"
}

main
