# arch-xiaomi-sheng

Arch Linux ARM 软件包集合和构建系统，为 **Xiaomi Pad 6S Pro 12.4 (SM8550-AB, 代号 sheng)** 提供硬件支持。

基于 [ianchb/debian-sheng](https://github.com/ianchb/debian-sheng) 移植到 Arch Linux 生态，使用 PKGBUILD 构建。

## 软件包列表

| 包名 | 描述 | 源 |
|---|---|---|
| `hexagonrpc` | Qualcomm Hexagon DSP FastRPC 通信库与守护进程 | [lzxcr/hexagonrpc](https://github.com/lzxcr/hexagonrpc) |
| `libssc` | Qualcomm Sensor Core 传感器库 | [DylanVanAssche/libssc](https://codeberg.org/DylanVanAssche/libssc) |
| `iio-sensor-proxy` | IIO 传感器到 D-Bus 的代理（带 SSC 支持） | [hadess/iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy) |
| `xiaomi-sheng-sensors` | 小米平板 6S Pro 传感器配置文件 | 从 debian-sheng 提取 |
| `alsa-ucm-xiaomi-sheng` | ALSA UCM2 音频配置 | 从 debian-sheng 提取 |
| `linux-xiaomi-sheng` | 主线内核 + 模块 + DTB（预编译 .deb 解包） | [ianchb/sm8550-mainline](https://github.com/ianchb/sm8550-mainline) |
| `linux-firmware-sheng` | 固件 blob（替代 linux-firmware-qcom 等） | [ianchb/sheng-firmware](https://github.com/ianchb/sheng-firmware) |
| `mkinitcpio-bootflash` | 通用 A/B 启动刷写 mkinitcpio 钩子 | 本地维护 |
| `xiaomi-sheng-devauth` | 小米官方键盘认证守护进程 | [ianchb/sheng_devauth](https://github.com/ianchb/sheng_devauth) |
| `xiaomi-mipps-auth` | MiPPS/PPS 充电器自动认证 | [ianchb/xiaomi-mipps-auth](https://github.com/ianchb/xiaomi-mipps-auth) |
| `xiaomi-charger-mode` | 充电模式用户态程序（framebuffer 充电界面） | [ianchb/xiaomi-charger-mode](https://github.com/ianchb/xiaomi-charger-mode) |
| `xiaomi-pen-status` | 小米 Focus 手写笔状态托盘工具 | [ianchb/xiaomi-pen-status](https://github.com/ianchb/xiaomi-pen-status) |
| `xiaomi-sheng-fingerprint` | 指纹 (FPC1553 QTEE) 支持 | [ianchb/xiaomi-sheng-fingerprint](https://github.com/ianchb/xiaomi-sheng-fingerprint) |
| `xiaomi-sheng-keyboard-helper` | 键盘辅助工具 | [ianchb/xiaomi-sheng-keyboard-helper](https://github.com/ianchb/xiaomi-sheng-keyboard-helper) |
| `xiaomi-sheng-thp` | NT36532E 触控处理器 | [ianchb/xiaomi-sheng-thp](https://github.com/ianchb/xiaomi-sheng-thp) |

## 软件包来源与 Arch 适配

本仓库 8 个硬件支持包直接跟踪 [ianchb](https://github.com/ianchb) 的上游仓库
（[debian-sheng](https://github.com/ianchb/debian-sheng) 的姊妹项目）。
上游主要面向 Debian/Android 生态发布，以下列出每个包的来源、版本追踪方式，
以及为适配 Arch Linux 生态所做的修正。

| 包名 | 上游仓库 | 版本追踪 | 上游分发形态 |
|---|---|---|---|
| `linux-xiaomi-sheng` | [ianchb/sm8550-mainline](https://github.com/ianchb/sm8550-mainline) | Release tag（预编译 .deb） | Debian 内核包 |
| `linux-firmware-sheng` | [ianchb/sheng-firmware](https://github.com/ianchb/sheng-firmware) | git master HEAD | 裸固件文件仓库 |
| `xiaomi-sheng-devauth` | [ianchb/sheng_devauth](https://github.com/ianchb/sheng_devauth) | git main HEAD（`rN.<sha>`） | C 源码 + Makefile |
| `xiaomi-mipps-auth` | [ianchb/xiaomi-mipps-auth](https://github.com/ianchb/xiaomi-mipps-auth) | Release tag `0.21` | 纯 Python 脚本 + Debian 打包目录 |
| `xiaomi-pen-status` | [ianchb/xiaomi-pen-status](https://github.com/ianchb/xiaomi-pen-status) | Release tag `v0.2.3` | Qt6 源码（qmake） |
| `xiaomi-sheng-thp` | [ianchb/xiaomi-sheng-thp](https://github.com/ianchb/xiaomi-sheng-thp) | Release tag `v0.3.9` | C++20 源码（Makefile） |
| `xiaomi-sheng-keyboard-helper` | [ianchb/xiaomi-sheng-keyboard-helper](https://github.com/ianchb/xiaomi-sheng-keyboard-helper) | Release tag `v0.2.0` | C 源码（Makefile） |
| `xiaomi-sheng-fingerprint` | [ianchb/xiaomi-sheng-fingerprint](https://github.com/ianchb/xiaomi-sheng-fingerprint) | Release tag `v0.1.4` | 源码 + prebuilt 二进制（meson） |

### linux-xiaomi-sheng（内核）

- 上游仅发布 **Debian 预编译 .deb**：PKGBUILD 直接下载 .deb 并解包 `data.tar.*`，
  **跳过 dpkg 安装脚本与触发器**，不依赖 Debian 工具链。
- 将 `boot/Image.gz` 解压为标准 **AArch64 `Image`** 放入 `/boot`（而非 Android boot.img），
  并把独立 DTB、`config-*`、`System.map-*` 一并装入 `/boot`。
- Debian 的 initramfs-tools 触发器替换为 Arch 的 **mkinitcpio**：包内自动生成
  `/etc/mkinitcpio.d/linux-xiaomi-sheng.preset`（initramfs 输出
  `/boot/initramfs-sheng.img`），配合 `post_install` 钩子生成 initramfs。
- 模块装入 `/usr/lib/modules`（Arch FHS），并以 `provides/conflicts` 对齐 Arch 内核包
  （`linux`、`linux-aarch64`），避免与发行版内核共存冲突。
- 解包后统一修正文件/目录权限（`fakeroot` 下构建无所有权问题）。

### linux-firmware-sheng（固件）

- 上游**无 Release**，git clone master HEAD 构建时取最新提交。
- 裸固件文件树整体复制到 `/usr/lib/firmware`（Arch FHS 惯例）。
- `provides`/`conflicts` 声明替代 Arch 官方 `linux-firmware-qcom`、
  `linux-firmware-atheros`、`linux-firmware-cirrus`，避免固件包冲突。
- `options=('!strip')`，并对固件文件统一做 目录 755 / 文件 644 的权限修正。

### xiaomi-sheng-devauth（键盘认证）

- 上游**无 Release**，跟踪 git main HEAD；`pkgver()` 用
  `git rev-list --count` + 短 SHA 自动生成版本（如 `r5.bac03b5`）。
- 上游为 C 源码 + Makefile（静态链接自带 `libs/*.a`），Arch 下直接 `make` 编译，
  二进制装入 `/usr/bin`。
- 上游**不提供 systemd 单元**（由 debian-sheng 的 postinst 生成）：systemd 服务
  由本仓库 `files/install/` 维护，并与其依赖的 `qteesupplicant.service` 联动
  （上游 PATCH 复用 qteesupplicant 的 RPMB listener）。
- pacman 不会自动启用服务，需手动 `systemctl enable xiaomi-sheng-devauth.service`
  （见下文「手动后处理」）。

### xiaomi-mipps-auth（充电认证）

- 纯 Python 脚本（GPL-2.0），上游以 Debian 包结构分发（内含 `DEBIAN/` 打包目录）。
- 二进制装入 `/usr/lib/xiaomi-mipps-auth/`（Debian 的 `libexec` 惯例 → Arch 路径），
  systemd 服务的 `ExecStart` 与 udev 规则的 `RUN` 路径**同步修正**。
- systemd 服务、udev 规则由本仓库 `files/install/` 维护（修正路径并保留
  `flock` 防重入语义）。
- 依赖映射：`python3 → python`、`libglib2.0-bin → glib2`、`udev → systemd`。

### xiaomi-pen-status（手写笔托盘）

- Qt6 托盘小工具，上游以 qmake 工程 + `build-deb.sh` 分发；Arch 直接用
  `qmake6 && make`，不引入 Debian 打包脚本。
- 自启动：上游按 XDG autostart 约定分发 → Arch 安装
  `/etc/xdg/autostart/xiaomi-pen-status.desktop`（sed 归一化 `Exec` 为纯托盘启动，
  不弹窗）。
- 图标装入 `hicolor` 主题（`/usr/share/icons/hicolor/scalable/apps`）。
- 依赖映射：Debian 的 `qt6-base-dev` 等 → Arch `qt6-base`/`qt6-svg`/`hicolor-icon-theme`。

### xiaomi-sheng-thp（触控处理器）

- `v0.3.9` 起链接 **libssc**（Focus Pen Pro posture 传感器路径）与 **glib2**：
  新增 `depends`/`makedepends`，并加入构建系统依赖映射
  （`PKG_DEPS[xiaomi-sheng-thp]="libssc"`，经 `makechrootpkg -I` 注入 chroot）。
- 上游 Makefile 默认 `LIBEXECDIR=$(PREFIX)/libexec/...`（Debian 惯例）→
  构建时传 `LIBEXECDIR=/usr/lib/xiaomi-sheng-thp`（Arch FHS）。
- 上游 systemd 单元指向 libexec 路径 → 本仓库 `files/install/` 提供修正版
  （`ExecStart` 指向 Arch 路径）；`v0.3.9` 上游新增
  `RuntimeDirectory=xiaomi-sheng-thp`（守护进程向 `/run/xiaomi-sheng-thp/` 写
  Focus Pen Pro ready 状态），本地单元同步补齐。
- `optdepends` 声明 `xiaomi-pen-status`（上游推荐但非必需）。

### xiaomi-sheng-keyboard-helper（键盘辅助）

- `prepare()` 中 sed 将 Makefile 的 `/usr/libexec/` 全局替换为
  `/usr/lib/<pkg>/`（Debian libexec 惯例 → Arch FHS）。
- 服务拆分：折叠角服务为**系统级**（`Wants/After=adsprpcd_sensorspd.service`，
  注意 Arch 包 hexagonrpc 的单元名带下划线，与 Debian 的 `adsprpcd-sensorspd`
  不同），麦克风静音指示为 **per-user 服务**（`systemd --user`）。
- 本地 systemd 单元（`files/install/`）修正 `ExecStart` 路径，覆盖
  `make install` 带入的上游单元；udev 规则沿用上游（无 libexec 引用）。

### xiaomi-sheng-fingerprint（指纹）

- 上游同时含源码与 prebuilt 二进制：构建时以 `scripts/build-backend.sh` +
  `scripts/build-libfprint.sh`（meson/ninja）本地编译 FPC QTEE backend 与
  libfprint 驱动，并以 `sha256sum -c prebuilt/aarch64/SHA256SUMS` 校验第三方
  QTEE/Mink 运行时。
- **私有安装**：FPC 版 libfprint 装入 `/usr/lib/xiaomi-sheng-fingerprint/`，
  **不覆盖发行版 libfprint**，通过 fprintd systemd drop-in 的
  `LD_LIBRARY_PATH` 暴露给 fprintd。
- 多架构路径修正：Debian multiarch 的 `/usr/lib/aarch64-linux-gnu/qtee-listeners`
  → Arch 的 `/usr/lib/qtee-listeners`；`/usr/libexec/` → `/usr/lib/<pkg>/`
  （sfsconfig/qteesupplicant 单元）。
- systemd 单元（sfsconfig、qteesupplicant）、udev 规则、fprintd drop-in 由
  本仓库 `files/install/` 维护。
- 依赖映射：`libfprint`（源码构建，需 pixman/libgusb/glib2 等）→ Arch
  `pixman`/`libgusb`/`glib2`，fprintd 来自官方仓库。

## 构建系统

### 前置要求

- Arch Linux ARM (aarch64) 环境
- 安装 `base-devel` 组以及必要工具：

```bash
pacman -S --needed base-devel git arch-install-scripts devtools
```

- 若在非 aarch64 环境交叉构建，还需安装 `qemu-user-static-bin`

### 快速开始

```bash
# 全流程一键
make all

# 或分步执行
./scripts/package-files.sh   # ① 打包 files/ 预置文件
make build                   # ② 在 clean chroot 中按拓扑序构建所有包
make repo                    # ③ 创建本地 pacman 仓库
make rootfs                  # ④ 用 pacstrap 组装可刷写的 rootfs.img
```

### 分步说明

**步骤 ① — package-files.sh**

将 `files/{direct,install}/` 下各包目录合并打包为 `pkgs/<pkg>/files.tar.gz`，供 PKGBUILD 引用。

```bash
./scripts/package-files.sh           # 打包所有包
./scripts/package-files.sh --pkg hexagonrpc  # 仅打包指定包
```

**步骤 ② — build-pkgs.sh**

按依赖拓扑分 4 个 tier 依次构建：

```
Tier 0: hexagonrpc, libssc, linux-firmware-sheng, linux-xiaomi-sheng
Tier 1: iio-sensor-proxy (depends: libssc)
Tier 2: xiaomi-sheng-sensors (depends: iio-sensor-proxy)
Tier 3: 其余 9 个包（alsa-ucm-xiaomi-sheng, xiaomi-charger-mode,
        mkinitcpio-bootflash, xiaomi-sheng-devauth, xiaomi-mipps-auth,
        xiaomi-pen-status, xiaomi-sheng-fingerprint,
        xiaomi-sheng-keyboard-helper, xiaomi-sheng-thp）
```

其中 `xiaomi-sheng-thp`（v0.3.9 起）与 `iio-sensor-proxy`、`xiaomi-sheng-sensors`
一样通过 `-I` 注入 chroot 内的 `libssc` 进行构建（见 `build-pkgs.sh` 的 `PKG_DEPS`）。

支持粒度控制：

```bash
./scripts/build-pkgs.sh --tier 0          # 只构建 tier 0
./scripts/build-pkgs.sh --from libssc     # 从 libssc 开始
./scripts/build-pkgs.sh --skip linux-xiaomi-sheng  # 跳过指定包
```

**步骤 ③ — build-repo.sh**

将所有构建好的 `.pkg.tar.*` 注册为本地 pacman 仓库（`out/repo/sheng.db.tar.gz`），并生成 pacman.conf 片段。

**步骤 ④ — mkrootfs.sh**

用 pacstrap 创建 ext4 格式的 rootfs 镜像：

```bash
# 默认配置（无桌面环境）
./scripts/mkrootfs.sh

# 带 KDE Plasma 桌面
./scripts/mkrootfs.sh --desktop kde

# 带 GNOME 桌面 + 额外包
./scripts/mkrootfs.sh --desktop gnome --extra "firefox vim htop"

# 完整参数
./scripts/mkrootfs.sh \
  --desktop kde \
  --hostname sheng \
  --user myuser \
  --password mypass \
  --size 8192
```

### 配置

编辑 `scripts/config.sh` 控制全流程参数：

```bash
BUILD_CHROOT=/var/lib/archbuild   # clean chroot 路径
KERNEL_PREBUILT_TAG="7.2.0"       # 内核 .deb 的 GitHub release tag
ROOTFS_DESKTOP="none"             # none | kde | gnome
ROOTFS_HOSTNAME="sheng"
ROOTFS_USER="alarm"
ROOTFS_SIZE_MB=4096
```

## 手动后处理

与 Debian 构建不同，Arch Linux 的 `pacman` 在安装包时不会自动启用 systemd 服务。以下服务需要手动启用：

### 必需服务

```bash
# FastRPC 传感器 DSP 守护进程（传感器工作的前提）
sudo systemctl enable adsprpcd_sensorspd.service
sudo systemctl start  adsprpcd_sensorspd.service

# 传感器代理（由 xiaomi-sheng-sensors 的 udev 规则触发）
# 安装 xiaomi-sheng-sensors 后需重载 udev 并重启服务
sudo udevadm control --reload
sudo systemctl try-restart iio-sensor-proxy.service
```

### 可选服务

```bash
# 键盘认证（使用小米官方键盘时启用）
sudo systemctl enable xiaomi-sheng-devauth.service
sudo systemctl start  xiaomi-sheng-devauth.service

# 指纹支持
sudo systemctl enable sfsconfig.service
sudo systemctl start  sfsconfig.service
sudo systemctl enable qteesupplicant.service
sudo systemctl start  qteesupplicant.service

# MiPPS 充电认证
sudo systemctl enable xiaomi-mipps-auth.service
sudo systemctl start  xiaomi-mipps-auth.service

# 充电模式（关机状态下充电显示界面）
# 仅在内核 cmdline 包含 androidboot.mode=charger 时激活
sudo systemctl enable xiaomi-charger-mode.service

# 触控处理守护进程
sudo systemctl enable xiaomi-sheng-thp.service
sudo systemctl start  xiaomi-sheng-thp.service
```

### 内核初始化

安装 `linux-xiaomi-sheng` 后需要生成 initramfs（包安装后会自动运行 `post_install`，但如果没有，手动执行）：

```bash
sudo mkinitcpio -p linux-xiaomi-sheng
```

### 关于 debian-sheng 自动 vs arch-xiaomi-sheng 手动的差异

| 功能 | debian-sheng | arch-xiaomi-sheng |
|---|---|---|
| adsprpcd_sensorspd | postinst 自动启用 | **需手动** `systemctl enable` |
| xiaomi-sheng-devauth | postinst 自动启用 | **需手动** `systemctl enable` |
| sfsconfig / qteesupplicant | postinst 自动启用 | **需手动** `systemctl enable` |
| mkinitcpio | 由 deb 包触发器运行 | **需手动**（或依赖 post_install 钩子） |
| udev 规则重载 | postinst 自动执行 | **需手动** `udevadm control --reload` |

### 刷写方法

构建完成后，将 `out/rootfs/rootfs.img` 刷写到设备：

```bash
# 进入 fastboot 模式
fastboot flash root rootfs.img
fastboot reboot
```

## 目录结构

```
arch-xiaomi-sheng/
├── Makefile                          # 便捷入口
├── files/                            # 本地维护的预置文件
│   ├── direct/                       #   直接拷贝的数据文件（ALSA UCM、传感器配置）
│   │   ├── alsa-ucm-xiaomi-sheng/
│   │   └── xiaomi-sheng-sensors/
│   └── install/                      #   需要安装的系统集成文件（systemd 单元、udev 规则）
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
│   ├── config.sh                     # 全局构建配置
│   ├── clean.sh                      # 清理构建产物（--keep-cache 保留源码缓存）
│   ├── package-files.sh              # 将 files/{direct,install}/ 打包为 pkgs/<pkg>/files.tar.gz
│   ├── build-pkgs.sh                 # ① 按拓扑序构建包
│   ├── build-repo.sh                 # ② 创建本地仓库
│   └── mkrootfs.sh                   # ③ 组装 rootfs 镜像
├── pkgs/                             # 15 个 PKGBUILD 包
│   ├── hexagonrpc/
│   ├── libssc/
│   ├── iio-sensor-proxy/
│   ├── xiaomi-sheng-sensors/
│   ├── alsa-ucm-xiaomi-sheng/
│   ├── linux-xiaomi-sheng/
│   ├── linux-firmware-sheng/
│   ├── mkinitcpio-bootflash/
│   ├── xiaomi-sheng-devauth/
│   ├── xiaomi-mipps-auth/
│   ├── xiaomi-charger-mode/
│   ├── xiaomi-pen-status/
│   ├── xiaomi-sheng-fingerprint/
│   ├── xiaomi-sheng-keyboard-helper/
│   └── xiaomi-sheng-thp/
├── docs/
│   ├── DESIGN.md                     # 构建系统设计文档
│   ├── preprocessing.md              # files/ 预处理操作记录
│   └── files-restructure.md          # files/ 集中化管理设计
└── out/                              # 构建输出 (.gitignore)
    ├── pkgs/                         # 构建好的 .pkg.tar.*
    ├── repo/                         # pacman 数据库
    └── rootfs/                       # rootfs.img
```

## 维护说明

- 更新预编译内核：修改 `config.sh` 中的 `KERNEL_PREBUILT_TAG`，并同步
  `pkgs/linux-xiaomi-sheng/PKGBUILD` 的 `pkgver`/`_tag`/`sha256sums`
- `files/{direct,install}/` 中的本地文件更新后，运行 `./scripts/package-files.sh` 重新打包 `files.tar.gz`
- 有固定 Release tag 的包使用**真实 sha256 校验和**；仅 git HEAD 快照包
  （`linux-firmware-sheng`、`xiaomi-sheng-devauth`、`hexagonrpc`）与本地生成的
  `files.tar.gz` 因内容随构建变化仍使用 `sha256sums=('SKIP')`
- 更新 tag 型包时，用 `sha256sum <新 tarball>` 计算并同步 `sha256sums`
- 在 `makechrootpkg` clean chroot 环境下构建时，`fakeroot` 自动处理文件所属权，无需显式 `chown`

## 致谢

- [map220v](https://github.com/map220v) — 内核移植
- [ianchb](https://github.com/ianchb) — debian-sheng 打包
- [DylanVanAssche](https://codeberg.org/DylanVanAssche) — libssc 库
