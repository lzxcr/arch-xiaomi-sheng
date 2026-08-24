# arch-xiaomi-sheng 构建系统设计

## 1. 目标

为 Xiaomi Pad 6S Pro 12.4 (sheng, SM8550-AB) 构建 Arch Linux ARM 硬件支持包 + 可刷写 rootfs 镜像。

## 2. 总体流程

```
files/ (预置文件)            config.sh
      │                           │
      ▼                           ▼
package-files.sh ──────► build-pkgs.sh ──────► build-repo.sh ──────► mkrootfs.sh
  (打包 files/ → files.tar.gz)  (clean chroot 构建)  (建 pacman 仓库)   (pacstrap 组装镜像)
```

## 3. 目录结构

```
arch-xiaomi-sheng/
├── Makefile                      # 便捷入口
├── files/                         # 本地预置文件（分两类）
│   ├── direct/                    #   直接拷贝的数据文件（ALSA UCM、传感器配置）
│   │   ├── alsa-ucm-xiaomi-sheng/
│   │   └── xiaomi-sheng-sensors/
│   └── install/                   #   需要安装的系统集成文件（systemd、udev 规则）
│       ├── hexagonrpc/
│       ├── mkinitcpio-bootflash/
│       ├── xiaomi-charger-mode/
│       ├── xiaomi-mipps-auth/
│       ├── xiaomi-sheng-devauth/
│       ├── xiaomi-sheng-fingerprint/
│       ├── xiaomi-sheng-keyboard-helper/
│       ├── xiaomi-sheng-sensors/
│       └── xiaomi-sheng-thp/
├── scripts/
│   ├── config.sh                 # 全局配置（用户可编辑）
│   ├── clean.sh                  # 清理构建产物（--keep-cache 保留源码缓存）
│   ├── package-files.sh          # ① 将 files/{direct,install}/ 打包为 files.tar.gz
│   ├── build-pkgs.sh             # ② 按依赖拓扑序在 clean chroot 中构建
│   ├── build-repo.sh             # ③ 创建本地 pacman 仓库
│   └── mkrootfs.sh               # ④ pacstrap 引导 + 生成 rootfs.img
├── pkgs/                         # 15 个 PKGBUILD 包（Arch Linux 规范）
│   ├── hexagonrpc/               #   Qualcomm Hexagon DSP FastRPC 通信
│   ├── libssc/                   #   Qualcomm Sensor Core 库
│   ├── iio-sensor-proxy/         #   IIO→D-Bus 代理 (+SSC 支持)
│   ├── xiaomi-sheng-sensors/     #   传感器配置文件集
│   ├── alsa-ucm-xiaomi-sheng/    #   ALSA UCM2 音频配置
│   ├── linux-xiaomi-sheng/       #   预编译内核 + 模块 + DTB
│   ├── linux-firmware-sheng/     #   固件 blob（替代上游 firmware 包）
│   ├── mkinitcpio-bootflash/     #   A/B 启动刷写 mkinitcpio 钩子
│   ├── xiaomi-sheng-devauth/     #   键盘认证守护进程
│   ├── xiaomi-mipps-auth/        #   MiPPS/PPS 充电认证
│   ├── xiaomi-charger-mode/      #   充电模式用户态程序
│   ├── xiaomi-pen-status/        #   手写笔状态托盘
│   ├── xiaomi-sheng-fingerprint/ #   指纹 FPC1553 QTEE 支持
│   ├── xiaomi-sheng-keyboard-helper/ # 键盘辅助工具
│   └── xiaomi-sheng-thp/         #   NT36532E 触控处理器
└── out/                          # 构建输出 (.gitignore)
    ├── pkgs/                     # *.pkg.tar.*
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
KERNEL_PREBUILT_TAG="7.2.0"

# 输出
OUT_DIR="$PWD/out"

# Rootfs 配置
ROOTFS_DESKTOP="none"              # none | kde | gnome
ROOTFS_EXTRA_PKGS=""               # 额外包（空格分隔）
ROOTFS_HOSTNAME="sheng"
ROOTFS_USER="alarm"
ROOTFS_SIZE_MB=4096
```

### 4.2 package-files.sh — 打包本地预置文件

```bash
#!/bin/bash
# 作用：将 files/{direct,install}/<pkg>/ 下的预置文件合并打包为 pkgs/<pkg>/files.tar.gz
# 输入：files/{direct,install}/ 中各子目录
# 输出：pkgs/*/files.tar.gz
```

**操作**：
1. 遍历 `files/{direct,install}/` 下每个包目录（取并集）
2. 合并到临时目录后打包为 `pkgs/<pkg>/files.tar.gz`（排除 `preprocess.sh`）
3. PKGBUILD 通过 `source=("files.tar.gz")` 引用

**文件映射**：

| 来源 (debian-sheng) | 目标 (files/) |
|---|---|
| `patches/adsprpcd-sensorspd.service` | `files/install/hexagonrpc/adsprpcd_sensorspd.service`（文件名 `-` → `_`） |
| `sheng-sensors-files/usr/share/qcom/` | `files/direct/xiaomi-sheng-sensors/usr/share/` |
| `sheng-sensors-files/usr/lib/` (systemd + udev) | `files/install/xiaomi-sheng-sensors/lib/`（drop-in 服务名修正） |
| `sheng-devauth/` 中 .service + qtee.conf | `files/install/xiaomi-sheng-devauth/usr/lib/systemd/system/` |
| `usr/share/alsa/ucm2/` | `files/direct/alsa-ucm-xiaomi-sheng/usr/` |

### 4.3 build-pkgs.sh — 构建包

```bash
#!/bin/bash
# 作用：按拓扑序在 clean chroot 中构建全部 15 个包
# 输入：config.sh + pkgs/*/PKGBUILD
# 输出：out/pkgs/*.pkg.tar.*
```

**构建拓扑**（4 个 tier，同 tier 可并行）：

```
Tier 0 (无内部依赖):
  hexagonrpc, libssc, linux-firmware-sheng, linux-xiaomi-sheng
       │
Tier 1 (依赖 libssc):
  iio-sensor-proxy
       │
Tier 2 (依赖 iio-sensor-proxy):
  xiaomi-sheng-sensors
       │
Tier 3 (无内部交叉依赖):
  alsa-ucm-xiaomi-sheng, xiaomi-charger-mode, mkinitcpio-bootflash,
  xiaomi-sheng-devauth, xiaomi-mipps-auth, xiaomi-pen-status,
  xiaomi-sheng-fingerprint, xiaomi-sheng-keyboard-helper, xiaomi-sheng-thp
```

**构建方式**：
- 检查 / 创建 clean chroot：`mkarchroot $BUILD_CHROOT base-devel`
- 逐包（同 tier 可并行）：`makechrootpkg -c -r $BUILD_CHROOT -- --syncdeps --noconfirm --skippgpcheck`
- 跨包依赖通过 `makechrootpkg -I` 注入 chroot（`PKG_DEPS` 表：iio-sensor-proxy → libssc，xiaomi-sheng-sensors → iio-sensor-proxy，xiaomi-sheng-thp → libssc）
- 产出 `.pkg.tar.*` 收集到 `out/pkgs/`

**参数**：
- `--tier N`：仅构建指定 tier
- `--from PKG`：从某包开始
- `--skip PKG1,PKG2`：跳过指定包

### 4.4 build-repo.sh — 建仓库

```bash
#!/bin/bash
# 作用：将 out/pkgs/*.pkg.tar.* 注册为本地 pacman 仓库
# 输出：out/repo/sheng.db.tar.gz + out/sheng-repo.conf
```

**操作**：
1. `cp out/pkgs/*.pkg.tar.* out/repo/`
2. `repo-add out/repo/sheng.db.tar.gz out/repo/*.pkg.tar.*`
3. 生成 `out/sheng-repo.conf`：
```ini
[sheng]
SigLevel = Never
Server = file:///path/to/out/repo
```

### 4.5 mkrootfs.sh — 组装 rootfs

```bash
#!/bin/bash
# 作用：用 pacstrap 创建 Arch ARM rootfs 并输出可刷写的镜像
# 输入：config.sh + out/repo/
# 输出：out/rootfs/rootfs.img
```

**操作**：
1. 创建空白镜像：`dd if=/dev/zero of=rootfs.img bs=1M count=$ROOTFS_SIZE_MB`
2. 格式化：`mkfs.ext4 rootfs.img`
3. 挂载到临时目录
4. `pacstrap -K /mnt base base-devel linux-aarch64 linux-firmware ...`（需在 aarch64 环境或 qemu-user-static）
5. 追加 `sheng-repo.conf` 并复制本地仓库包到 `/opt/sheng-repo`
6. `arch-chroot /mnt pacman -Syu --noconfirm` 安装全部 15 个 sheng 包
7. 可选：安装桌面环境（KDE/GNOME）
8. 配置 hostname / locale / 用户 / 网络，启用 NetworkManager 与桌面 DM
9. `mkinitcpio -p linux-xiaomi-sheng` 生成 initramfs
10. 清理 pacman 缓存、卸载、fsck

**桌面环境安装**：
- `ROOTFS_DESKTOP=kde`：安装 `plasma-meta konsole dolphin plasma-nm plasma-pa kscreen powerdevil spectacle gwenview`，启用 sddm
- `ROOTFS_DESKTOP=gnome`：安装 `gnome gnome-tweaks gnome-browser-connector gdm networkmanager`，启用 gdm
- `ROOTFS_DESKTOP=none`：跳过

## 5. 包依赖关系矩阵

| 包名 | 运行时依赖 | 构建依赖 | 源类型 |
|---|---|---|---|
| hexagonrpc | glibc, systemd | meson, ninja, pkgconf, json-c, git | GitHub git clone |
| libssc | glib2, protobuf-c, libqmi | devtools, meson, ninja, pkgconf, protobuf | Codeberg tar.gz |
| iio-sensor-proxy | glib2, systemd, libgudev, polkit, dbus, **libssc** | devtools, meson, ninja, pkgconf | GitLab tar.gz |
| xiaomi-sheng-sensors | **iio-sensor-proxy** | — | files.tar.gz（本地维护） |
| alsa-ucm-xiaomi-sheng | alsa-ucm-conf | — | files.tar.gz（本地维护） |
| linux-xiaomi-sheng | kmod, mkinitcpio | — | GitHub Release .deb |
| linux-firmware-sheng | — (conflicts linux-firmware-*) | git | GitHub git clone |
| mkinitcpio-bootflash | android-tools, mkinitcpio | — | files.tar.gz（本地维护） |
| xiaomi-sheng-devauth | systemd | git, make, gcc | GitHub git clone |
| xiaomi-mipps-auth | python, systemd, util-linux, glib2 | — | GitHub tar.gz |
| xiaomi-charger-mode | python, systemd, util-linux | — | GitHub tar.gz + files.tar.gz |
| xiaomi-pen-status | qt6-base, qt6-svg, hicolor-icon-theme | qt6-base, make | GitHub tar.gz |
| xiaomi-sheng-fingerprint | fprintd, systemd, glibc, glib2, pixman, libgusb | gcc, meson, ninja, pkgconf, git | GitHub tar.gz |
| xiaomi-sheng-keyboard-helper | glibc, glib2, systemd | gcc, make, pkgconf | GitHub tar.gz |
| xiaomi-sheng-thp | bluez, glibc, gcc-libs, glib2, **libssc**, systemd | gcc, make, pkgconf, glib2, libssc | GitHub tar.gz |

## 6. 设计决策记录

| 决策 | 选项 | 理由 |
|---|---|---|
| 最终产出 | 包仓库 + rootfs 镜像 | 既满足安装到已有系统，也支持全新刷写 |
| 脚本拆法 | 5 脚本（config/package-files/build/repo/mkrootfs）+ clean | 关注点分离，可独立调试每一步 |
| 构建环境 | clean chroot (makechrootpkg) | Arch 规范，避免宿主污染 |
| 内核 | 仅预编译二进制 | 用户选择，避免全量内核编译 |
| 源文件获取 | 本地 files/{direct,install}/ 维护（package-files.sh 打包） | 不再依赖运行时 clone，所有预置文件版本受控 |
| rootfs 配置 | config.sh 单文件 | 简单可控，所有参数集中管理 |
| 包构建方式 | PKGBUILD | Arch Linux 标准，社区熟悉 |
