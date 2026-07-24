# arch-xiaomi-sheng 构建系统实现计划

> **For agentic workers:** 使用 superpowers:executing-plans 逐步实现。

**Goal:** 为 arch-xiaomi-sheng 实现 4 脚本构建系统：config.sh → fetch-sources.sh → build-pkgs.sh → build-repo.sh → mkrootfs.sh

**架构:** 4 个 shell 脚本 + 1 个配置文件，单个脚本独立可执行，按序串联完成从源文件提取到 rootfs 镜像产出的全流程。所有 PKGBUILD 已就绪，脚本负责编排它们。

**Tech Stack:** Bash, pacstrap/makechrootpkg (arch-build), repo-add, mkfs.ext4

---

### Task 1: scripts/config.sh — 全局配置文件

**Files:**
- Create: `scripts/config.sh`

- [ ] **Step 1: 写入 config.sh**

```bash
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
KERNEL_PREBUILT_TAG="${KERNEL_PREBUILT_TAG:-7.1.4-kbd}"

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
```

- [ ] **Step 2: 验证语法**

Run: `bash -n scripts/config.sh`
Expected: 无输出（语法正确）

- [ ] **Step 3: Commit**

```bash
git add scripts/config.sh
git commit -m "feat: add global build config (config.sh)"
```

---

### Task 2: scripts/fetch-sources.sh — 从 debian-sheng 提取本地源文件

**Files:**
- Create: `scripts/fetch-sources.sh`

- [ ] **Step 1: 写入 fetch-sources.sh**

```bash
#!/usr/bin/env bash
#
# fetch-sources.sh —— 从 ianchb/debian-sheng clone 并提取
# PKGBUILD 引用的本地源文件到对应 pkgs/ 目录。
#
# 用法: ./scripts/fetch-sources.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/config.sh
source "$SCRIPT_DIR/config.sh"

TMP_CLONE="/tmp/debian-sheng-$$"
REPO_URL="https://github.com/ianchb/debian-sheng.git"

cleanup() { rm -rf "$TMP_CLONE"; }
trap cleanup EXIT

echo "==> 克隆 ianchb/debian-sheng ..."
git clone --depth=1 "$REPO_URL" "$TMP_CLONE"

echo "==> 提取文件到 pkgs/ ..."

# 1. adsprpcd-sensorspd.service → pkgs/fastrpc/
mkdir -p "$PKG_DIR/fastrpc"
if [ -f "$TMP_CLONE/patches/adsprpcd-sensorspd.service" ]; then
  cp "$TMP_CLONE/patches/adsprpcd-sensorspd.service" \
     "$PKG_DIR/fastrpc/adsprpcd-sensorspd.service"
  echo "  ✓ fastrpc/adsprpcd-sensorspd.service"
else
  echo "  ! fastrpc/adsprpcd-sensorspd.service 未找到，已跳过"
fi

# 2. wait_for_qmi_service.patch → pkgs/libssc/
mkdir -p "$PKG_DIR/libssc"
if [ -f "$TMP_CLONE/patches/wait_for_qmi_service.patch" ]; then
  cp "$TMP_CLONE/patches/wait_for_qmi_service.patch" \
     "$PKG_DIR/libssc/wait_for_qmi_service.patch"
  echo "  ✓ libssc/wait_for_qmi_service.patch"
else
  echo "  ! libssc/wait_for_qmi_service.patch 未找到，已跳过"
fi

# 3. sheng-sensors-files/ → pkgs/xiaomi-sheng-sensors/
mkdir -p "$PKG_DIR/xiaomi-sheng-sensors"
if [ -d "$TMP_CLONE/sheng-sensors-files" ]; then
  rm -rf "$PKG_DIR/xiaomi-sheng-sensors/sheng-sensors-files"
  cp -r "$TMP_CLONE/sheng-sensors-files" \
     "$PKG_DIR/xiaomi-sheng-sensors/sheng-sensors-files"
  echo "  ✓ xiaomi-sheng-sensors/sheng-sensors-files/ (共 $(find "$PKG_DIR/xiaomi-sheng-sensors/sheng-sensors-files" -type f | wc -l) 个文件)"
else
  echo "  ! xiaomi-sheng-sensors/sheng-sensors-files/ 未找到，已跳过"
fi

echo "==> 完成。"
```

- [ ] **Step 2: 验证语法**

Run: `bash -n scripts/fetch-sources.sh`
Expected: 无输出

- [ ] **Step 3: 测试运行（会真正 clone 并提取文件）**

Run: `cd /home/lzx/项目/arch-xiaomi-sheng && bash scripts/fetch-sources.sh`
Expected: 成功 clone 并提取 3 个文件/目录

- [ ] **Step 4: 验证提取结果**

Run: `ls -la pkgs/fastrpc/adsprpcd-sensorspd.service pkgs/libssc/wait_for_qmi_service.patch && test -d pkgs/xiaomi-sheng-sensors/sheng-sensors-files && echo "所有文件已就绪"`
Expected: 显示 3 个文件/目录都存在

- [ ] **Step 5: Commit**

```bash
git add scripts/fetch-sources.sh
git commit -m "feat: add fetch-sources.sh (extract files from debian-sheng)"
```

---

### Task 3: scripts/build-pkgs.sh — 按拓扑序构建所有包

**Files:**
- Create: `scripts/build-pkgs.sh`

- [ ] **Step 1: 写入 build-pkgs.sh**

```bash
#!/usr/bin/env bash
#
# build-pkgs.sh —— 按拓扑依赖序在 clean chroot 中构建所有包
#
# 用法: ./scripts/build-pkgs.sh [--tier N] [--from PKG] [--skip PKG1,PKG2]
#
# 依赖拓扑:
#   Tier 0: fastrpc libssc linux-firmware-sheng linux-xiaomi-sheng
#   Tier 1: iio-sensor-proxy (depends: libssc)
#   Tier 2: xiaomi-sheng-sensors (depends: iio-sensor-proxy)
#   Tier 3: xiaomi-sheng-devauth xiaomi-mipps-auth xiaomi-pen-status
#           xiaomi-sheng-fingerprint xiaomi-sheng-keyboard-helper xiaomi-sheng-thp
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/config.sh
source "$SCRIPT_DIR/config.sh"

# ── 拓扑定义 ──────────────────────────────────────────────
declare -A PKG_TIERS
PKG_TIERS[0]="fastrpc libssc linux-firmware-sheng linux-xiaomi-sheng"
PKG_TIERS[1]="iio-sensor-proxy"
PKG_TIERS[2]="xiaomi-sheng-sensors"
PKG_TIERS[3]="xiaomi-sheng-devauth xiaomi-mipps-auth xiaomi-pen-status xiaomi-sheng-fingerprint xiaomi-sheng-keyboard-helper xiaomi-sheng-thp"

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
  # --tier 过滤
  if [ -n "$TIER_FILTER" ]; then
    local found=0
    for p in ${PKG_TIERS[$TIER_FILTER]}; do
      [ "$p" = "$pkg" ] && found=1 && break
    done
    [ "$found" -eq 0 ] && return 1
  fi
  # --from 过滤
  if [ -n "$FROM_PKG" ]; then
    local started=0
    for p in $ALL_PKGS; do
      [ "$p" = "$FROM_PKG" ] && started=1
      if [ "$started" -eq 0 ]; then continue; fi
      [ "$p" = "$pkg" ] && break
    done
    [ "$started" -eq 0 ] && return 1
    # 如果 --from 指定的包本身还没到，且当前包不是它，跳过
    local after_from=0
    for p in $ALL_PKGS; do
      [ "$p" = "$FROM_PKG" ] && after_from=1
      [ "$p" = "$pkg" ] && break
    done
    [ "$after_from" -eq 0 ] && return 1
  fi
  # --skip 过滤
  if [ -n "$SKIP_PKGS" ]; then
    IFS=',' read -ra skip_arr <<< "$SKIP_PKGS"
    for s in "${skip_arr[@]}"; do
      [ "$s" = "$pkg" ] && return 1
    done
  fi
  return 0
}

# ── 构建前检查 ────────────────────────────────────────────

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

# ── 主构建循环 ────────────────────────────────────────────

main() {
  mkdir -p "$OUT_PKGS_DIR"

  check_prereqs
  init_chroot

  # 按 Tier 顺序构建
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

      # 如果该包有已构建的依赖，先用 -I 注入到 chroot
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

      # 执行 makechrootpkg
      (cd "$pkgdir" && makechrootpkg -c -r "$BUILD_CHROOT" \
        "${install_args[@]}" \
        -- --syncdeps --noconfirm --skippgpcheck)

      # 收集产物
      msg "收集 $pkg 构建产物 ..."
      find "$pkgdir" -maxdepth 1 -name '*.pkg.tar.*' -exec mv {} "$OUT_PKGS_DIR/" \;

      # 清理 PKGBUILD 所在目录的残留包
      (cd "$pkgdir" && rm -f *.pkg.tar.*)

      # 安装到 chroot 供后续 tier 使用
      local built_pkg
      built_pkg=$(find "$OUT_PKGS_DIR" -name "${pkg}-*.pkg.tar.*" | head -1)
      if [ -n "$built_pkg" ]; then
        msg "  安装 $pkg 到 chroot（供后续 tier）..."
        sudo arch-nspawn "$BUILD_CHROOT/root" \
          pacman -U --noconfirm "$built_pkg" 2>/dev/null || true
      fi

      msg "✓ $pkg 构建完成"
    done
  done

  msg "══════ 全部构建完成 ══════"
  echo "产物目录: $OUT_PKGS_DIR"
  ls -1 "$OUT_PKGS_DIR"/*.pkg.tar.* 2>/dev/null || echo "(无包产物)"
}

main "$@"
```

- [ ] **Step 2: 验证语法**

Run: `bash -n scripts/build-pkgs.sh`
Expected: 无输出

- [ ] **Step 3: Commit**

```bash
git add scripts/build-pkgs.sh
git commit -m "feat: add build-pkgs.sh (topological tiered build in clean chroot)"
```

---

### Task 4: scripts/build-repo.sh — 创建本地 pacman 仓库

**Files:**
- Create: `scripts/build-repo.sh`

- [ ] **Step 1: 写入 build-repo.sh**

```bash
#!/usr/bin/env bash
#
# build-repo.sh —— 将 out/pkgs/*.pkg.tar.* 注册为本地 pacman 仓库
#
# 用法: ./scripts/build-repo.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/config.sh
source "$SCRIPT_DIR/config.sh"

msg()  { echo -e "\033[1;34m==>\033[0m $*"; }
error(){ echo -e "\033[1;31m!!>\033[0m $*" >&2; }

main() {
  mkdir -p "$OUT_REPO_DIR"

  local pkg_count
  pkg_count=$(find "$OUT_PKGS_DIR" -name '*.pkg.tar.*' -type f | wc -l)

  if [ "$pkg_count" -eq 0 ]; then
    error "没有找到已构建的包在 $OUT_PKGS_DIR"
    error "请先执行 ./scripts/build-pkgs.sh"
    exit 1
  fi

  msg "复制 $pkg_count 个包到仓库目录 ..."
  cp "$OUT_PKGS_DIR"/*.pkg.tar.* "$OUT_REPO_DIR/"

  msg "创建仓库数据库: $OUT_REPO_DIR/sheng.db.tar.gz ..."
  repo-add "$OUT_REPO_DIR/sheng.db.tar.gz" "$OUT_REPO_DIR"/*.pkg.tar.*

  # 生成 pacman.conf 片段
  local repo_conf="$OUT_DIR/sheng-repo.conf"
  cat > "$repo_conf" <<-EOF
# sheng 本地仓库 — 由 build-repo.sh 自动生成
# 追加到 /etc/pacman.conf 使用
[sheng]
SigLevel = Never
Server = file://$(readlink -f "$OUT_REPO_DIR")
EOF

  msg "══════ 仓库构建完成 ══════"
  echo "仓库目录: $OUT_REPO_DIR"
  echo "仓库配置: $repo_conf"
  echo ""
  echo "在 rootfs 中使用本仓库:"
  echo "  cat $repo_conf >> /mnt/etc/pacman.conf"
  echo "  或使用 mkrootfs.sh 自动完成"
}

main "$@"
```

- [ ] **Step 2: 验证语法**

Run: `bash -n scripts/build-repo.sh`
Expected: 无输出

- [ ] **Step 3: Commit**

```bash
git add scripts/build-repo.sh
git commit -m "feat: add build-repo.sh (create local pacman repo from built packages)"
```

---

### Task 5: scripts/mkrootfs.sh — pacstrap 组装 rootfs 镜像

**Files:**
- Create: `scripts/mkrootfs.sh`

- [ ] **Step 1: 写入 mkrootfs.sh**

```bash
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
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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

cleanup() {
  if mountpoint -q "$MNT_DIR" 2>/dev/null; then
    msg "卸载 $MNT_DIR ..."
    sudo umount -R "$MNT_DIR" || true
  fi
  [ -d "$MNT_DIR" ] && rmdir "$MNT_DIR" 2>/dev/null || true
  [ -f "$LOOP_DEV" ] && sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
}
trap cleanup EXIT

# ── 检查依赖 ──────────────────────────────────────────────

check_prereqs() {
  local missing=0
  for cmd in pacstrap arch-chroot mkfs.ext4 losetup; do
    if ! command -v "$cmd" &>/dev/null; then
      error "缺少命令: $cmd（请安装 arch-install-scripts 和 e2fsprogs）"
      missing=1
    fi
  done
  # 检查 qemu-user-static（如非 aarch64 环境）
  if [ "$(uname -m)" != "aarch64" ]; then
    if ! command -v binfmt_misc &>/dev/null && [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
      msg "检测到非 aarch64 环境，确认已安装 qemu-user-static-bin"
      msg "  pacman -S qemu-user-static-bin 或 qemu-user-static"
    fi
  fi
  [ "$missing" -eq 1 ] && exit 1
}

# ── 桌面环境包映射 ────────────────────────────────────────

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

# ── 主流程 ────────────────────────────────────────────────

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
    # 更新仓库 Server 指向
    echo "Server = file:///opt/sheng-repo" | sudo tee -a "$MNT_DIR/etc/pacman.conf" > /dev/null
  fi

  # 7. 安装 sheng 包
  msg "安装 sheng 硬件支持包 ..."
  local SHENG_PKGS="fastrpc libssc iio-sensor-proxy xiaomi-sheng-sensors \
                     linux-xiaomi-sheng linux-firmware-sheng \
                     xiaomi-sheng-devauth xiaomi-mipps-auth \
                     xiaomi-pen-status xiaomi-sheng-fingerprint \
                     xiaomi-sheng-keyboard-helper xiaomi-sheng-thp"
  sudo arch-chroot "$MNT_DIR" pacman -Syu --noconfirm $SHENG_PKGS

  # 8. 安装桌面环境（可选）
  local DESKTOP_PKGS
  DESKTOP_PKGS=$(desktop_pkgs "$ROOTFS_DESKTOP")
  if [ -n "$DESKTOP_PKGS" ]; then
    msg "安装桌面环境: $ROOTFS_DESKTOP ..."
    sudo arch-chroot "$MNT_DIR" pacman -Syu --noconfirm $DESKTOP_PKGS
  fi

  # 9. 安装额外包
  if [ -n "$ROOTFS_EXTRA_PKGS" ]; then
    msg "安装额外包: $ROOTFS_EXTRA_PKGS ..."
    sudo arch-chroot "$MNT_DIR" pacman -Syu --noconfirm $ROOTFS_EXTRA_PKGS
  fi

  # 10. 系统配置
  msg "配置系统 ..."

  # hostname
  echo "$ROOTFS_HOSTNAME" | sudo tee "$MNT_DIR/etc/hostname" > /dev/null

  # hosts
  cat <<-EOF | sudo tee "$MNT_DIR/etc/hosts" > /dev/null
127.0.0.1   localhost
127.0.1.1   $ROOTFS_HOSTNAME.localdomain $ROOTFS_HOSTNAME
::1         localhost ip6-localhost ip6-loopback
EOF

  # locale
  sudo sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' "$MNT_DIR/etc/locale.gen"
  sudo arch-chroot "$MNT_DIR" locale-gen
  echo "LANG=en_US.UTF-8" | sudo tee "$MNT_DIR/etc/locale.conf" > /dev/null

  # 用户
  if [ -n "$ROOTFS_USER" ]; then
    msg "创建用户 $ROOTFS_USER ..."
    sudo arch-chroot "$MNT_DIR" useradd -m -G wheel -s /bin/bash "$ROOTFS_USER" 2>/dev/null || true
    echo "$ROOTFS_USER:$ROOTFS_PASSWORD" | sudo chpasswd -R "$MNT_DIR"
  fi

  # sudo
  sudo sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "$MNT_DIR/etc/sudoers"

  # 网络
  sudo arch-chroot "$MNT_DIR" systemctl enable NetworkManager

  # 如果桌面=gnome，启用 gdm
  if [ "$ROOTFS_DESKTOP" = "gnome" ]; then
    sudo arch-chroot "$MNT_DIR" systemctl enable gdm
  elif [ "$ROOTFS_DESKTOP" = "kde" ]; then
    sudo arch-chroot "$MNT_DIR" systemctl enable sddm 2>/dev/null || true
  fi

  # 启用 initramfs 生成（linux-xiaomi-sheng post_install 会调用）
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
```

- [ ] **Step 2: 验证语法**

Run: `bash -n scripts/mkrootfs.sh`
Expected: 无输出

- [ ] **Step 3: Commit**

```bash
git add scripts/mkrootfs.sh
git commit -m "feat: add mkrootfs.sh (pacstrap-based rootfs image builder)"
```

---

### Task 6: 根目录入口脚本 + .gitignore + 整体验证

**Files:**
- Create: `Makefile`（可选，便捷入口）
- Create: `.gitignore` 补充

- [ ] **Step 1: 写入 Makefile（便捷入口）**

```makefile
# arch-xiaomi-sheng 构建系统 — 便捷入口
# 用法: make <target>

SHELL := /bin/bash
.SHELLFLAGS = -euo pipefail -c

.PHONY: all fetch build repo rootfs clean

all: fetch build repo rootfs

# ① 从 debian-sheng 提取源文件
fetch:
	@echo "==> [1/4] 提取源文件 ..."
	@bash scripts/fetch-sources.sh

# ② 构建所有包
build:
	@echo "==> [2/4] 构建包 ..."
	@bash scripts/build-pkgs.sh

# ③ 创建本地仓库
repo:
	@echo "==> [3/4] 创建仓库 ..."
	@bash scripts/build-repo.sh

# ④ 组装 rootfs
rootfs:
	@echo "==> [4/4] 组装 rootfs 镜像 ..."
	@bash scripts/mkrootfs.sh

# 清理所有构建产物
clean:
	rm -rf out/pkgs out/repo out/rootfs out/sheng-repo.conf
	@echo "已清理构建产物"
```

- [ ] **Step 2: 写入/更新 .gitignore**

```gitignore
# 构建输出
/out/

# 构建临时文件
*.pkg.tar.*
*.log
```

- [ ] **Step 3: 确保 out/.gitkeep 存在**

```bash
touch out/.gitkeep
git add -f out/.gitkeep
```

- [ ] **Step 4: 整体结构检查**

Run: `cd /home/lzx/项目/arch-xiaomi-sheng && ls -la scripts/ && cat Makefile`
Expected: 所有 4 脚本 + config.sh + Makefile 均存在

- [ ] **Step 5: 最终提交**

```bash
git add Makefile .gitignore out/.gitkeep
git add -u  # 还有之前 commit 遗漏的文件
git commit -m "feat: add build system entry point (Makefile + gitignore)"
```

- [ ] **Step 6: 加载 verification-before-completion 验证产出**

调用 verification-before-completion skill 验证所有文件完整性和语法正确性。
