#!/usr/bin/env bash
#
# mkrootfs.sh —— 用 pacstrap 创建可刷写的 Arch Linux ARM rootfs 镜像
#
# 用法: ./scripts/mkrootfs.sh
#   ./scripts/mkrootfs.sh --desktop kde
#   ./scripts/mkrootfs.sh --desktop gnome --extra "firefox vim"
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=scripts/config.sh
source "$SCRIPT_DIR/config.sh"

# ── 解析参数覆盖 ──────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desktop)  ROOTFS_DESKTOP="$2";   shift 2 ;;
    --extra)    ROOTFS_EXTRA_PKGS="$2"; shift 2 ;;
    --hostname) ROOTFS_HOSTNAME="$2";  shift 2 ;;
    --user)     ROOTFS_USER="$2";      shift 2 ;;
    --password) ROOTFS_PASSWORD="$2";  shift 2 ;;
    --size)     ROOTFS_SIZE_MB="$2";   shift 2 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

# ── 辅助函数 ──────────────────────────────────────────────
msg()   { echo -e "\033[1;34m==>\033[0m $*"; }
error() { echo -e "\033[1;31m!!>\033[0m $*" >&2; }

MNT_DIR=""
LOOP_DEV=""

cleanup() {
  if mountpoint -q "$MNT_DIR" 2>/dev/null; then
    msg "卸载 $MNT_DIR ..."
    sudo umount -R "$MNT_DIR" || true
  fi
  if [ -d "$MNT_DIR" ]; then
    rmdir "$MNT_DIR" 2>/dev/null || true
  fi
  if [ -n "$LOOP_DEV" ] && [ -b "$LOOP_DEV" ]; then
    sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
  fi
}
trap cleanup EXIT

check_prereqs() {
  local missing=0
  for cmd in pacstrap arch-chroot mkfs.ext4 losetup; do
    if ! command -v "$cmd" &>/dev/null; then
      error "缺少命令: $cmd（请安装 arch-install-scripts 和 e2fsprogs）"
      missing=1
    fi
  done
  if [ "$(uname -m)" != "aarch64" ]; then
    if ! command -v binfmt_misc &>/dev/null && [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
      msg "检测到非 aarch64 环境，确认已安装 qemu-user-static-bin"
      msg "  pacman -S qemu-user-static-bin 或 qemu-user-static"
    fi
  fi
  [ "$missing" -eq 1 ] && exit 1
}

desktop_pkgs() {
  case "${1:-none}" in
    kde)
      echo "plasma-meta konsole dolphin plasma-nm plasma-pa \
            kscreen powerdevil spectacle gwenview"
      ;;
    gnome)
      echo "gnome gnome-tweaks gnome-browser-connector \
            gdm networkmanager"
      ;;
    none|"")
      echo ""
      ;;
    *)
      error "不支持的桌面: $1（可选: none, kde, gnome）"
      exit 1
      ;;
  esac
}

main() {
  check_prereqs

  mkdir -p "$OUT_ROOTFS_DIR"
  MNT_DIR=$(mktemp -d)
  local IMG_FILE="$OUT_ROOTFS_DIR/rootfs.img"

  # 1. 创建空白镜像文件
  msg "创建 $ROOTFS_SIZE_MB MiB 空白镜像 ..."
  dd if=/dev/zero of="$IMG_FILE" bs=1M count="$ROOTFS_SIZE_MB" status=progress

  # 2. 格式化
  msg "格式化为 ext4 ..."
  mkfs.ext4 -F "$IMG_FILE"

  # 3. 挂载
  msg "挂载镜像到 $MNT_DIR ..."
  sudo mount "$IMG_FILE" "$MNT_DIR"

  # 4. pacstrap 安装基础系统
  msg "pacstrap 基础系统（base linux-aarch64 ...）..."
  sudo pacstrap -K "$MNT_DIR" base base-devel linux-aarch64 \
    linux-firmware vim sudo networkmanager

  # 5. 复制本地仓库配置
  msg "配置本地 sheng 仓库 ..."
  if [ -f "$OUT_DIR/sheng-repo.conf" ]; then
    # shellcheck disable=SC2002 # cat 以普通用户读取，tee 以 root 写入
    cat "$OUT_DIR/sheng-repo.conf" | sudo tee -a "$MNT_DIR/etc/pacman.conf" > /dev/null
  else
    error "未找到本地仓库配置: $OUT_DIR/sheng-repo.conf（请先执行 build-repo.sh）"
    exit 1
  fi

  # 6. 复制本地仓库包文件到镜像内
  local REPO_IN_MNT="$MNT_DIR/opt/sheng-repo"
  sudo mkdir -p "$REPO_IN_MNT"
  if [ -d "$OUT_REPO_DIR" ] && [ "$(ls -A "$OUT_REPO_DIR" 2>/dev/null)" ]; then
    msg "复制本地仓库包到镜像 ..."
    sudo cp "$OUT_REPO_DIR"/* "$REPO_IN_MNT/"
    echo "Server = file:///opt/sheng-repo" | sudo tee -a "$MNT_DIR/etc/pacman.conf" > /dev/null
  fi

  # 7. 安装 sheng 包
  msg "安装 sheng 硬件支持包 ..."
  local SHENG_PKGS="hexagonrpc libssc iio-sensor-proxy xiaomi-sheng-sensors \
                     alsa-ucm-xiaomi-sheng linux-xiaomi-sheng linux-firmware-sheng \
                     mkinitcpio-bootflash xiaomi-sheng-devauth xiaomi-mipps-auth \
                     xiaomi-charger-mode xiaomi-pen-status xiaomi-sheng-fingerprint \
                     xiaomi-sheng-keyboard-helper xiaomi-sheng-thp"
  # shellcheck disable=SC2086 # 有意按空格拆分为多个包名
  sudo arch-chroot "$MNT_DIR" pacman -Syu --noconfirm $SHENG_PKGS

  # 8. 安装桌面环境（可选）
  local DESKTOP_PKGS
  DESKTOP_PKGS=$(desktop_pkgs "$ROOTFS_DESKTOP")
  if [ -n "$DESKTOP_PKGS" ]; then
    msg "安装桌面环境: $ROOTFS_DESKTOP ..."
    # shellcheck disable=SC2086 # 有意按空格拆分为多个包名
    sudo arch-chroot "$MNT_DIR" pacman -Syu --noconfirm $DESKTOP_PKGS
  fi

  # 9. 安装额外包
  if [ -n "$ROOTFS_EXTRA_PKGS" ]; then
    msg "安装额外包: $ROOTFS_EXTRA_PKGS ..."
    # shellcheck disable=SC2086 # 有意按空格拆分为多个包名
    sudo arch-chroot "$MNT_DIR" pacman -Syu --noconfirm $ROOTFS_EXTRA_PKGS
  fi

  # 10. 系统配置
  msg "配置系统 ..."

  echo "$ROOTFS_HOSTNAME" | sudo tee "$MNT_DIR/etc/hostname" > /dev/null

  cat <<-HOSTS | sudo tee "$MNT_DIR/etc/hosts" > /dev/null
127.0.0.1   localhost
127.0.1.1   $ROOTFS_HOSTNAME.localdomain $ROOTFS_HOSTNAME
::1         localhost ip6-localhost ip6-loopback
HOSTS

  sudo sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' "$MNT_DIR/etc/locale.gen"
  sudo arch-chroot "$MNT_DIR" locale-gen
  echo "LANG=en_US.UTF-8" | sudo tee "$MNT_DIR/etc/locale.conf" > /dev/null

  if [ -n "$ROOTFS_USER" ]; then
    msg "创建用户 $ROOTFS_USER ..."
    sudo arch-chroot "$MNT_DIR" useradd -m -G wheel -s /bin/bash "$ROOTFS_USER" 2>/dev/null || true
    echo "$ROOTFS_USER:$ROOTFS_PASSWORD" | sudo chpasswd -R "$MNT_DIR"
  fi

  sudo sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "$MNT_DIR/etc/sudoers"
  sudo arch-chroot "$MNT_DIR" systemctl enable NetworkManager

  if [ "$ROOTFS_DESKTOP" = "gnome" ]; then
    sudo arch-chroot "$MNT_DIR" systemctl enable gdm
  elif [ "$ROOTFS_DESKTOP" = "kde" ]; then
    sudo arch-chroot "$MNT_DIR" systemctl enable sddm 2>/dev/null || true
  fi

  sudo arch-chroot "$MNT_DIR" mkinitcpio -p linux-xiaomi-sheng

  # 11. 清理 pacman 缓存
  sudo arch-chroot "$MNT_DIR" pacman -Scc --noconfirm 2>/dev/null || true

  # 12. 卸载
  msg "卸载镜像 ..."
  sudo umount -R "$MNT_DIR"

  # 13. fsck 验证
  msg "验证文件系统 ..."
  fsck.ext4 -f "$IMG_FILE" 2>&1 | tail -3

  # 14. 输出信息
  local img_size
  img_size=$(du -h "$IMG_FILE" | cut -f1)
  msg "══════ Rootfs 镜像构建完成 ══════"
  echo "镜像文件: $IMG_FILE"
  echo "镜像大小: $img_size / ${ROOTFS_SIZE_MB}MiB"
  echo ""
  echo "刷写方法（需进入 fastboot）:"
  echo "  fastboot flash root rootfs.img"
  echo "  fastboot reboot"
}

main "$@"
