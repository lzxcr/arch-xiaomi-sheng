#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
#
# arch-xiaomi-sheng —— 全局构建配置
# 所有脚本 source 此文件获取参数
#

# This file is sourced by scripts/lib/common.sh. PROJECT_DIR is derived from
# this repository's location, so commands work from any current directory.
: "${PROJECT_DIR:?scripts/config.sh must be sourced through scripts/lib/common.sh}"

# ── 构建环境 ──────────────────────────────────────────────
# clean chroot 路径（由 archbuild/makechrootpkg 使用）
BUILD_CHROOT="${BUILD_CHROOT:-/var/lib/archbuild}"

# ── 输出目录 ──────────────────────────────────────────────
OUT_DIR="${OUT_DIR:-$PROJECT_DIR/out}"
[[ "$OUT_DIR" == /* ]] || OUT_DIR="$PROJECT_DIR/$OUT_DIR"

# ── Rootfs 配置 ───────────────────────────────────────────
ROOTFS_DESKTOP="${ROOTFS_DESKTOP:-none}"       # none | kde | gnome
ROOTFS_EXTRA_PKGS="${ROOTFS_EXTRA_PKGS:-}"      # 额外 pacman 包（空格分隔）
ROOTFS_HOSTNAME="${ROOTFS_HOSTNAME:-sheng}"
ROOTFS_USER="${ROOTFS_USER:-alarm}"
ROOTFS_PASSWORD="${ROOTFS_PASSWORD:-alarm}"
ROOTFS_SIZE_MB="${ROOTFS_SIZE_MB:-4096}"         # rootfs.img 大小 (MiB)
ROOTFS_PARTLABEL="${ROOTFS_PARTLABEL:-root}"      # 内核 root=PARTLABEL= 值
ROOTFS_KERNEL_CMDLINE="${ROOTFS_KERNEL_CMDLINE:-root=PARTLABEL=${ROOTFS_PARTLABEL} rw rootwait}"

# ── 派生路径（通常不需修改） ──────────────────────────────
PKG_DIR="$PROJECT_DIR/pkgs"
OUT_PKGS_DIR="$OUT_DIR/pkgs"
OUT_REPO_DIR="$OUT_DIR/repo"
OUT_ROOTFS_DIR="$OUT_DIR/rootfs"
