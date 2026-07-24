# arch-xiaomi-sheng 构建系统设计

## 1. 目标

为 Xiaomi Pad 6S Pro 12.4 (sheng, SM8550-AB) 构建 Arch Linux ARM 硬件支持包 + 可刷写 rootfs 镜像。

## 2. 总体流程

```
debian-sheng (GitHub)          config.sh
      │                           │
      ▼                           ▼
fetch-sources.sh ──────► build-pkgs.sh ──────► build-repo.sh ──────► mkrootfs.sh
  (提取本地源文件)       (clean chroot 构建)    (建 pacman 仓库)     (pacstrap 组装镜像)
```

## 3. 目录结构

```
arch-xiaomi-sheng/
├── config.sh                     # 全局配置（用户可编辑）
├── scripts/
│   ├── fetch-sources.sh          # ① 从 ianchb/debian-sheng clone 并提取文件
│   ├── build-pkgs.sh             # ② 按依赖拓扑序在 clean chroot 中构建
│   ├── build-repo.sh             # ③ 创建本地 pacman 仓库
│   └── mkrootfs.sh               # ④ pacstrap 引导 + 生成 rootfs.img
├── pkgs/                         # 12 个 PKGBUILD 包（Arch Linux 规范）
│   ├── fastrpc/                  #   Qualcomm FastRPC DSP 通信
│   ├── libssc/                   #   Qualcomm Sensor Core 库
│   ├── iio-sensor-proxy/         #   IIO→D-Bus 代理 (+SSC 支持)
│   ├── xiaomi-sheng-sensors/     #   传感器配置文件集
│   ├── linux-xiaomi-sheng/       #   预编译内核 + 模块 + DTB
│   ├── linux-firmware-sheng/     #   固件 blob（替代上游 firmware 包）
│   ├── xiaomi-sheng-devauth/     #   键盘认证守护进程
│   ├── xiaomi-mipps-auth/        #   MiPPS/PPS 充电认证
│   ├── xiaomi-pen-status/        #   手写笔状态托盘
│   ├── xiaomi-sheng-fingerprint/ #   指纹 FPC1553 QTEE 支持
│   ├── xiaomi-sheng-keyboard-helper/ # 键盘辅助工具
│   └── xiaomi-sheng-thp/         #   NT36532E 触控处理器
└── out/                          # 构建输出 (.gitignore)
    ├── pkgs/                     # *.pkg.tar.xz
    ├── repo/                     # pacman DB
    └── rootfs/                   # rootfs.img + boot.img
```

## 4. 各脚本详设

### 4.1 config.sh — 全局配置

所有脚本 `source config.sh` 读取。用户编辑此文件即可控制全流程。

```bash
# 构建环境
BUILD_CHROOT=/var/lib/archbuild    # clean chroot 路径

# 内核
KERNEL_PREBUILT_REPO="ianchb/sm8550-mainline"
KERNEL_PREBUILT_TAG="7.1.4-kbd"

# 输出
OUT_DIR="$PWD/out"

# Rootfs 配置
ROOTFS_DESKTOP="none"              # none | kde | gnome
ROOTFS_EXTRA_PKGS=""               # 额外包（空格分隔）
ROOTFS_HOSTNAME="sheng"
ROOTFS_USER="alarm"
ROOTFS_SIZE_MB=4096
```

### 4.2 fetch-sources.sh — 提取源文件

```bash
#!/bin/bash
# 作用：从 ianchb/debian-sheng 提取 PKGBUILD 引用的本地文件
# 输入：无（自动 clone）
# 输出：补足 pkgs/ 下缺失的 source 文件
```

**操作**：
1. `git clone --depth=1 https://github.com/ianchb/debian-sheng /tmp/debian-sheng-src`
2. 提取文件映射：

| 来源 (debian-sheng) | 目标 (arch-xiaomi-sheng) |
|---|---|
| `patches/adsprpcd-sensorspd.service` | `pkgs/fastrpc/adsprpcd-sensorspd.service` |
| `patches/wait_for_qmi_service.patch` | `pkgs/libssc/wait_for_qmi_service.patch` |
| `sheng-sensors-files/` (整个目录) | `pkgs/xiaomi-sheng-sensors/sheng-sensors-files/` |

3. 清理临时目录

**幂等**：再次运行会覆盖更新。

### 4.3 build-pkgs.sh — 构建包

```bash
#!/bin/bash
# 作用：按拓扑序在 clean chroot 中构建全部 12 个包
# 输入：config.sh + pkgs/*/PKGBUILD
# 输出：out/pkgs/*.pkg.tar.xz
```

**构建拓扑**（3 个 tier，同 tier 可并行）：

```
Tier 0 (无内部依赖):
  fastrpc, libssc, linux-firmware-sheng, linux-xiaomi-sheng
       │
Tier 1 (依赖 libssc):
  iio-sensor-proxy
       │
Tier 2 (依赖 iio-sensor-proxy):
  xiaomi-sheng-sensors
       │
Tier 3 (无内部依赖):
  xiaomi-sheng-devauth, xiaomi-mipps-auth, xiaomi-pen-status,
  xiaomi-sheng-fingerprint, xiaomi-sheng-keyboard-helper, xiaomi-sheng-thp
```

**构建方式**：
- 检查 / 创建 clean chroot：`mkarchroot $BUILD_CHROOT base-devel`
- 逐包（同 tier 可并行）：`makechrootpkg -c -r $BUILD_CHROOT -- --syncdeps --noconfirm --skippgpcheck`
- 产出 `.pkg.tar.xz` 收集到 `out/pkgs/`
- 构建完成后在 repo 中安装给下一 tier 使用（通过 `makechrootpkg -I`）

**参数**：
- `--tier N`：仅构建指定 tier
- `--from PKG`：从某包开始
- `--skip PKG1,PKG2`：跳过指定包

### 4.4 build-repo.sh — 建仓库

```bash
#!/bin/bash
# 作用：将 out/pkgs/*.pkg.tar.xz 注册为本地 pacman 仓库
# 输出：out/repo/sheng.db + sheng.files
```

**操作**：
1. `cp out/pkgs/*.pkg.tar.xz out/repo/`
2. `repo-add out/repo/sheng.db.tar.gz out/repo/*.pkg.tar.xz`
3. 生成 `out/sheng-repo.conf`：
```ini
[options]
SigLevel = Never
[sheng]
Server = file:///path/to/out/repo
```

### 4.5 mkrootfs.sh — 组装 rootfs

```bash
#!/bin/bash
# 作用：用 pacstrap 创建 Arch ARM rootfs 并输出可刷写的镜像
# 输入：config.sh + out/repo/
# 输出：out/rootfs/rootfs.img + boot.img
```

**操作**：
1. 创建空白镜像：`dd if=/dev/zero of=rootfs.img bs=1M count=$ROOTFS_SIZE_MB`
2. 格式化：`mkfs.ext4 rootfs.img`
3. 挂载到临时目录
4. `pacstrap /mnt base`（需在 aarch64 环境或 qemu-user-static）
5. 复制 `sheng-repo.conf` 到 `/mnt/etc/pacman.conf` 追加
6. `arch-chroot /mnt pacman -Syu --noconfirm`
7. 安装所有 sheng 包
8. 可选：安装桌面环境（KDE/GNOME）
9. 配置 hostname / user / 网络
10. 卸载、fsck

**桌面环境安装**：
- `ROOTFS_DESKTOP=kde`：安装 `plasma-meta konsole dolphin`
- `ROOTFS_DESKTOP=gnome`：安装 `gnome gnome-tweaks`
- `ROOTFS_DESKTOP=none`：跳过

## 5. 包依赖关系矩阵

| 包名 | 运行时依赖 | 构建依赖 | 源类型 |
|---|---|---|---|
| fastrpc | systemd | autoconf, automake, libtool | GitHub tar.gz + 本地 .service |
| libssc | glib2, protobuf-c, libqmi | meson, ninja, pkgconf, protobuf, git | CodeBerg tar.gz + 本地 .patch |
| iio-sensor-proxy | glib2, systemd, gudev, polkit, dbus, **libssc** | meson, ninja, pkgconf | GitLab tar.gz |
| xiaomi-sheng-sensors | **iio-sensor-proxy** | — | 本地目录 |
| linux-xiaomi-sheng | kmod, mkinitcpio | — | GitHub Release .deb |
| linux-firmware-sheng | — (conflicts linux-firmware-*) | git | GitHub git clone |
| xiaomi-sheng-devauth | systemd | git, make, gcc | GitHub git clone |
| xiaomi-mipps-auth | python, systemd, util-linux, glib2 | — | GitHub tar.gz |
| xiaomi-pen-status | qt6-base, qt6-svg, hicolor-icon-theme | qt6-base, make | GitHub tar.gz |
| xiaomi-sheng-fingerprint | fprintd, systemd, glibc, glib2, pixman, libgusb | gcc, meson, ninja, pkgconf, git | GitHub tar.gz |
| xiaomi-sheng-keyboard-helper | glibc, glib2, systemd | gcc, make, pkgconf | GitHub tar.gz |
| xiaomi-sheng-thp | bluez, glibc, gcc-libs, systemd | gcc, make | GitHub tar.gz |

## 6. 设计决策记录

| 决策 | 选项 | 理由 |
|---|---|---|
| 最终产出 | 包仓库 + rootfs 镜像 | 既满足安装到已有系统，也支持全新刷写 |
| 脚本拆法 | 4 脚本（fetch/build/repo/mkrootfs） | 关注点分离，可独立调试每一步 |
| 构建环境 | clean chroot (makechrootpkg) | Arch 规范，避免宿主污染 |
| 内核 | 仅预编译二进制 | 用户选择，避免全量内核编译 |
| 源文件获取 | 自动 clone debian-sheng | 上游更新时只需重新 fetch，不持久化冗余副本 |
| rootfs 配置 | config.sh 单文件 | 简单可控，所有参数集中管理 |
| 包构建方式 | PKGBUILD | Arch Linux 标准，社区熟悉 |
