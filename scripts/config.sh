#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# arch-xiaomi-sheng —— 全局构建配置
# 所有脚本 source 此文件获取参数
#

# ── 构建环境 ──────────────────────────────────────────────
# clean chroot 路径（由 archbuild/makechrootpkg 使用）
BUILD_CHROOT="${BUILD_CHROOT:-/var/lib/archbuild}"

# ── 内核 ──────────────────────────────────────────────────
# 预编译内核来源（GitHub Release）
KERNEL_PREBUILT_REPO="${KERNEL_PREBUILT_REPO:-ianchb/sm8550-mainline}"
KERNEL_PREBUILT_TAG="${KERNEL_PREBUILT_TAG:-7.2.0}"

# ── 输出目录 ──────────────────────────────────────────────
OUT_DIR="${OUT_DIR:-$PWD/out}"

# ── Rootfs 配置 ───────────────────────────────────────────
ROOTFS_DESKTOP="${ROOTFS_DESKTOP:-none}"       # none | kde | gnome
ROOTFS_EXTRA_PKGS="${ROOTFS_EXTRA_PKGS:-}"      # 额外 pacman 包（空格分隔）
ROOTFS_HOSTNAME="${ROOTFS_HOSTNAME:-sheng}"
ROOTFS_USER="${ROOTFS_USER:-alarm}"
ROOTFS_PASSWORD="${ROOTFS_PASSWORD:-alarm}"
ROOTFS_SIZE_MB="${ROOTFS_SIZE_MB:-4096}"         # rootfs.img 大小 (MiB)

# ── 派生路径（通常不需修改） ──────────────────────────────
PKG_DIR="$PWD/pkgs"
SCRIPTS_DIR="$PWD/scripts"
OUT_PKGS_DIR="$OUT_DIR/pkgs"
OUT_REPO_DIR="$OUT_DIR/repo"
OUT_ROOTFS_DIR="$OUT_DIR/rootfs"
