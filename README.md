# arch-xiaomi-sheng

面向 **Xiaomi Pad 6S Pro 12.4（SM8550-AB，代号 sheng）** 的 Arch Linux ARM
硬件支持包集合与镜像构建系统。

仓库把上游源码、Debian 设备包和本地设备文件适配为 15 个标准 PKGBUILD，经过
clean chroot 构建后生成本地 pacman 仓库，并可进一步组装 `rootfs.img` 与
Android `boot.img`。

> 项目仍涉及预编译内核、闭源固件和直接刷写 A/B 启动分区。请先备份数据，并在
> 确认设备型号、分区布局和启动槽后操作。

## 工作原理

```text
files/{direct,install} ──► files.tar.gz ─┐
                                        ├─► PKGBUILD / clean chroot
上游 git、release、tarball ─────────────┘             │
                                                       ▼
                                              out/pkgs/*.pkg.tar.*
                                                       │
                                                       ▼
                                               out/repo (pacman)
                                                       │
                                                       ▼
                                         rootfs.img + boot.img
```

运行时的传感器主链路是：内核 FastRPC 设备节点触发 udev，udev 启动
`hexagonrpcd-adsp-sensorspd.service`；`hexagonrpcd` 将 Android 固件路径映射到
`/usr/share/qcom/...`，`libssc` 与 `iio-sensor-proxy` 再把 SSC 传感器暴露到
D-Bus。键盘折叠角服务依赖同一个 sensors PD。音频、触控、充电、指纹等功能由
各自的软件包、udev 规则和 systemd 单元接入。

更完整的构建与运行时说明见 [设计文档](docs/DESIGN.md)，本地文件来源见
[设备文件说明](docs/FILES.md)。

## 软件包

| 包 | 作用 | 上游 |
|---|---|---|
| `hexagonrpc` | Qualcomm FastRPC 反向 RPC 守护进程与工具 | [lzxcr/hexagonrpc](https://github.com/lzxcr/hexagonrpc) |
| `libssc` | Qualcomm Sensor Core 用户态库 | [DylanVanAssche/libssc](https://codeberg.org/DylanVanAssche/libssc) |
| `iio-sensor-proxy` | IIO/SSC 到 D-Bus 的传感器代理 | [hadess/iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy) |
| `xiaomi-sheng-sensors` | sheng 传感器配置、注册表与 udev 规则 | 本地设备文件 |
| `alsa-ucm-xiaomi-sheng` | ALSA UCM2 音频配置 | 本地设备文件 |
| `linux-xiaomi-sheng` | 预编译主线内核、模块和 DTB | [ianchb/sm8550-mainline](https://github.com/ianchb/sm8550-mainline) |
| `linux-firmware-sheng` | sheng 专用固件 | [ianchb/sheng-firmware](https://github.com/ianchb/sheng-firmware) |
| `mkinitcpio-bootflash` | 生成 Android boot.img 并在设备上更新 A/B boot | 本地维护 |
| `xiaomi-sheng-devauth` | 官方键盘认证 | [ianchb/sheng_devauth](https://github.com/ianchb/sheng_devauth) |
| `xiaomi-mipps-auth` | MiPPS/PPS 充电器认证 | [ianchb/xiaomi-mipps-auth](https://github.com/ianchb/xiaomi-mipps-auth) |
| `xiaomi-charger-mode` | 关机充电界面 | [ianchb/xiaomi-charger-mode](https://github.com/ianchb/xiaomi-charger-mode) |
| `xiaomi-pen-status` | Focus Pen 状态托盘 | [ianchb/xiaomi-pen-status](https://github.com/ianchb/xiaomi-pen-status) |
| `xiaomi-sheng-fingerprint` | FPC1553 QTEE 指纹支持 | [ianchb/xiaomi-sheng-fingerprint](https://github.com/ianchb/xiaomi-sheng-fingerprint) |
| `xiaomi-sheng-keyboard-helper` | 键盘折叠角与麦克风指示辅助 | [ianchb/xiaomi-sheng-keyboard-helper](https://github.com/ianchb/xiaomi-sheng-keyboard-helper) |
| `xiaomi-sheng-thp` | NT36532E 用户态触控处理 | [ianchb/xiaomi-sheng-thp](https://github.com/ianchb/xiaomi-sheng-thp) |

### HexagonRPC 版本

`hexagonrpc` 已更新到上游提交 `db659bd`（上游版本 0.6.0）。该版本从 C/Meson
整体迁移到 Rust/Cargo，要求 Rust 1.85+，并提供 `hexagonrpcd` 与
`sns-registrygen`。配方锁定完整提交哈希与 `Cargo.lock`，构建时运行工作区测试。

旧的 `adsprpcd_sensorspd.service` 已由
`hexagonrpcd-adsp-sensorspd.service` 取代。FastRPC 服务由包内 udev 规则按设备
节点自动启动，无需手动 enable。

## 构建

需要 Arch Linux ARM aarch64 环境。安装基础工具：

```bash
sudo pacman -S --needed base-devel git arch-install-scripts devtools ripgrep
```

在非 aarch64 宿主上还需正确配置 `qemu-user-static`/binfmt。项目脚本可以从任意
目录调用，不依赖当前 `$PWD`。

先运行快速检查：

```bash
make check
```

完整流程：

```bash
make all
```

也可以分步执行：

```bash
make files    # 生成确定性的 files.tar.gz
make build    # clean chroot 构建 15 个包
make repo     # 原子生成 out/repo
make rootfs   # 生成 rootfs.img 和 boot.img
```

直接运行 `make` 只显示帮助，不会意外启动耗时构建。

### 增量构建

包顺序与内部依赖集中定义在 `scripts/lib/packages.sh`，构建脚本不会再为一次局部
构建清空 `out/pkgs`。因此可以复用已构建依赖：

```bash
./scripts/build-pkgs.sh --stage 0
./scripts/build-pkgs.sh --from iio-sensor-proxy
./scripts/build-pkgs.sh --skip linux-xiaomi-sheng,linux-firmware-sheng
./scripts/build-pkgs.sh --list --stage 3
```

`--tier` 仍作为 `--stage` 的兼容别名。每个成功重建的包只替换自己的旧产物；
失败时保留此前产物。

### Rootfs 参数

默认配置位于 `scripts/config.sh`，也可用环境变量覆盖。常用示例：

```bash
make rootfs ROOTFS_ARGS='--desktop kde --size 8192'

./scripts/mkrootfs.sh \
  --desktop gnome \
  --hostname sheng \
  --user alarm \
  --password 'change-me' \
  --partlabel root \
  --size 8192
```

主要变量：

| 变量 | 默认值 | 含义 |
|---|---|---|
| `BUILD_CHROOT` | `/var/lib/archbuild` | devtools clean chroot 根目录 |
| `OUT_DIR` | `<项目>/out` | 所有输出目录 |
| `ROOTFS_DESKTOP` | `none` | `none`、`kde` 或 `gnome` |
| `ROOTFS_SIZE_MB` | `4096` | rootfs 镜像逻辑大小 |
| `ROOTFS_PARTLABEL` | `root` | 内核根分区 PARTLABEL |
| `ROOTFS_KERNEL_CMDLINE` | `root=PARTLABEL=root rw rootwait` | boot.img 内核命令行 |

rootfs 构建会把仓库复制到镜像内的 `/opt/sheng-repo`，不会写入仅宿主可见的
`file://` 路径。它也不会先安装会与设备内核冲突的 `linux-aarch64`。生成
initramfs 时设置 `BOOTFLASH_NO_FLASH=1`，确保构建宿主的分区不会被刷新。

## 安装后的服务

HexagonRPC、MiPPS 和 QTEE 入口均可由 udev 事件触发。以下长期服务按实际硬件
需求启用：

```bash
sudo systemctl enable --now xiaomi-sheng-thp.service
sudo systemctl enable --now xiaomi-sheng-devauth.service      # 官方键盘
sudo systemctl enable --now xiaomi-charger-mode.service      # 充电模式
sudo systemctl enable --now qteesupplicant.service           # 指纹/QTEE
```

安装新的 udev 规则后可以执行：

```bash
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=misc
```

## boot.img 与刷写

构建结果位于：

```text
out/rootfs/rootfs.img
out/rootfs/boot.img
```

示例假定根分区为 `root`、使用 slot B：

```bash
fastboot flash root out/rootfs/rootfs.img
fastboot flash boot_b out/rootfs/boot.img
fastboot reboot
```

`mkinitcpio-bootflash` 在已安装设备上会读取
`/boot/loader/entries/arch.conf`，生成 `/boot/boot.img`，并在检测到
`boot_a`/`boot_b` 分区时写入两槽。设置 `BOOTFLASH_NO_FLASH=1` 可只生成镜像：

```bash
sudo BOOTFLASH_NO_FLASH=1 mkinitcpio -p linux-xiaomi-sheng
```

## 维护

- 固定 release/tarball 必须更新真实校验和；git 源至少锁定完整 commit。
- 更新 `files/` 后运行 `make files`；归档使用固定顺序、时间和 owner，可重复生成。
- 新增或删除包时只改 `scripts/lib/packages.sh` 与对应 PKGBUILD，`make check` 会检测漂移。
- 更新内核需同步 `pkgs/linux-xiaomi-sheng/PKGBUILD` 的版本、URL 与校验和；
  `scripts/config.sh` 不维护一份无效的重复版本号。

## 致谢

- [map220v](https://github.com/map220v) — sheng 主线内核移植
- [ianchb](https://github.com/ianchb) — Debian 设备支持与各硬件工具
- [DylanVanAssche](https://codeberg.org/DylanVanAssche) — libssc
