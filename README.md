# arch-xiaomi-sheng

Arch Linux ARM 软件包集合和构建系统，为 **Xiaomi Pad 6S Pro 12.4 (SM8550-AB, 代号 sheng)** 提供硬件支持。

基于 [ianchb/debian-sheng](https://github.com/ianchb/debian-sheng) 移植到 Arch Linux 生态，使用 PKGBUILD 构建。

## 软件包列表

| 包名 | 描述 | 源 |
|---|---|---|
| `fastrpc` | Qualcomm FastRPC DSP 通信用户空间库 | [qualcomm/fastrpc](https://github.com/qualcomm/fastrpc) |
| `libssc` | Qualcomm Sensor Core 传感器库 | [DylanVanAssche/libssc](https://codeberg.org/DylanVanAssche/libssc) |
| `iio-sensor-proxy` | IIO 传感器到 D-Bus 的代理（带 SSC 支持） | [hadess/iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy) |
| `xiaomi-sheng-sensors` | 小米平板 6S Pro 传感器配置文件 | 从 debian-sheng 提取 |
| `alsa-ucm-xiaomi-sheng` | ALSA UCM2 音频配置 | 从 debian-sheng 提取 |
| `linux-xiaomi-sheng` | 主线内核 + 模块 + DTB（预编译 .deb 解包） | [ianchb/sm8550-mainline](https://github.com/ianchb/sm8550-mainline) |
| `linux-firmware-sheng` | 固件 blob（替代 linux-firmware-qcom 等） | [ianchb/sheng-firmware](https://github.com/ianchb/sheng-firmware) |
| `xiaomi-sheng-devauth` | 小米官方键盘认证守护进程 | [ianchb/sheng_devauth](https://github.com/ianchb/sheng_devauth) |
| `xiaomi-mipps-auth` | MiPPS/PPS 充电器自动认证 | [ianchb/xiaomi-mipps-auth](https://github.com/ianchb/xiaomi-mipps-auth) |
| `xiaomi-pen-status` | 小米 Focus 手写笔状态托盘工具 | [ianchb/xiaomi-pen-status](https://github.com/ianchb/xiaomi-pen-status) |
| `xiaomi-sheng-fingerprint` | 指纹 (FPC1553 QTEE) 支持 | [ianchb/xiaomi-sheng-fingerprint](https://github.com/ianchb/xiaomi-sheng-fingerprint) |
| `xiaomi-sheng-keyboard-helper` | 键盘辅助工具 | [ianchb/xiaomi-sheng-keyboard-helper](https://github.com/ianchb/xiaomi-sheng-keyboard-helper) |
| `xiaomi-sheng-thp` | NT36532E 触控处理器 | [ianchb/xiaomi-sheng-thp](https://github.com/ianchb/xiaomi-sheng-thp) |

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
./scripts/package-files.sh --pkg fastrpc  # 仅打包指定包
```

**步骤 ② — build-pkgs.sh**

按依赖拓扑分 4 个 tier 依次构建：

```
Tier 0: fastrpc, libssc, linux-firmware-sheng, linux-xiaomi-sheng
Tier 1: iio-sensor-proxy (depends: libssc)
Tier 2: xiaomi-sheng-sensors (depends: iio-sensor-proxy)
Tier 3: 剩余 6 个包（无内部交叉依赖）
```

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
KERNEL_PREBUILT_TAG="7.1.4-kbd"   # 内核 .deb 的 GitHub release tag
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
sudo systemctl enable sheng-devauth.service
sudo systemctl start  sheng-devauth.service

# 指纹支持
sudo systemctl enable sfsconfig.service
sudo systemctl start  sfsconfig.service
sudo systemctl enable qteesupplicant.service
sudo systemctl start  qteesupplicant.service

# MiPPS 充电认证
sudo systemctl enable xiaomi-mipps-auth.service
sudo systemctl start  xiaomi-mipps-auth.service

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
| sheng-devauth | postinst 自动启用 | **需手动** `systemctl enable` |
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
│       ├── fastrpc/
│       ├── xiaomi-mipps-auth/
│       ├── xiaomi-sheng-devauth/
│       ├── xiaomi-sheng-fingerprint/
│       ├── xiaomi-sheng-keyboard-helper/
│       ├── xiaomi-sheng-sensors/
│       └── xiaomi-sheng-thp/
├── scripts/
│   ├── config.sh                     # 全局构建配置
│   ├── package-files.sh              # 将 files/{direct,install}/ 打包为 pkgs/<pkg>/files.tar.gz
│   ├── build-pkgs.sh                 # ① 按拓扑序构建包
│   ├── build-repo.sh                 # ② 创建本地仓库
│   └── mkrootfs.sh                   # ③ 组装 rootfs 镜像
├── pkgs/                             # 13 个 PKGBUILD 包
│   ├── fastrpc/
│   ├── libssc/
│   ├── iio-sensor-proxy/
│   ├── xiaomi-sheng-sensors/
│   ├── alsa-ucm-xiaomi-sheng/
│   ├── linux-xiaomi-sheng/
│   ├── linux-firmware-sheng/
│   ├── xiaomi-sheng-devauth/
│   ├── xiaomi-mipps-auth/
│   ├── xiaomi-pen-status/
│   ├── xiaomi-sheng-fingerprint/
│   ├── xiaomi-sheng-keyboard-helper/
│   └── xiaomi-sheng-thp/
├── docs/
│   ├── DESIGN.md                     # 构建系统设计文档
│   ├── preprocessing.md              # files/ 预处理操作记录
│   ├── files-restructure.md          # files/ 集中化管理设计
│   └── superpowers/plans/            # 实现计划
└── out/                              # 构建输出 (.gitignore)
    ├── pkgs/                         # 构建好的 .pkg.tar.*
    ├── repo/                         # pacman 数据库
    └── rootfs/                       # rootfs.img
```

## 维护说明

- 更新预编译内核：修改 `config.sh` 中的 `KERNEL_PREBUILT_TAG`
- `files/{direct,install}/` 中的本地文件更新后，运行 `./scripts/package-files.sh` 重新打包 `files.tar.gz`
- 所有包使用 `sha256sums=('SKIP')`（因上游未提供校验和文件），实际构建时通过 HTTPS 传输保证完整性
- 在 `makechrootpkg` clean chroot 环境下构建时，`fakeroot` 自动处理文件所属权，无需显式 `chown`

## 致谢

- [map220v](https://github.com/map220v) — 内核移植
- [ianchb](https://github.com/ianchb) — debian-sheng 打包
- [DylanVanAssche](https://codeberg.org/DylanVanAssche) — libssc 库
