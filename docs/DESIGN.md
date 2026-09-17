# 构建系统与运行时设计

## 1. 边界

本仓库不是一个单体程序，而是 sheng 设备支持的“发行集成层”。它负责四件事：

1. 把不同上游的源码和二进制发布转换成 Arch 包；
2. 对 Debian/Android 路径、服务和依赖做 Arch 适配；
3. 在 clean chroot 中按内部依赖构建并发布本地 pacman 仓库；
4. 用该仓库组装可刷写的 rootfs 与 Android boot image。

内核开发、固件逆向、上游硬件程序开发不在本仓库内完成。`files/direct` 中的设备
blob 作为版本化输入保存，不参与重格式化或源码级重构。

## 2. 单一事实来源

| 数据 | 唯一来源 | 消费者 |
|---|---|---|
| 包名、阶段、内部构建依赖 | `scripts/lib/packages.sh` | `build-pkgs.sh`、`mkrootfs.sh`、`check.sh` |
| 用户可覆盖的构建参数 | `scripts/config.sh` | 全部构建脚本 |
| 本地维护的系统文件 | `files/{direct,install}/<pkg>` | `package-files.sh` |
| 上游版本、依赖、安装布局 | `pkgs/<pkg>/PKGBUILD` | makepkg/devtools |
| 生成物 | `out/` | repo、rootfs 与用户 |

路径统一由 `scripts/lib/common.sh` 从脚本位置推导。`OUT_DIR` 可以覆盖，但默认不再
依赖调用者的当前目录。

## 3. 构建数据流

```text
                         scripts/config.sh
                                 │
                                 ▼
files/direct ─┐          package manifest
              ├─ package-files ─────┐
files/install ┘                     │
                                    ▼
upstream source ───────────────► PKGBUILD
                                    │
                                    ▼
                         makechrootpkg clean chroot
                                    │
                                    ▼
                              out/pkgs
                                    │
                             repo-add (staging)
                                    │
                                    ▼
                              out/repo
                                    │
                           pacstrap + arch-chroot
                                    │
                                    ▼
                         rootfs.img + boot.img
```

### 3.1 本地文件归档

`package-files.sh` 合并同一包的 `direct/` 和 `install/` 内容；后者在路径冲突时
覆盖前者。归档固定条目顺序、mtime、uid 与 gid，因此相同输入产生相同
`files.tar.gz`。归档是派生物，不提交 Git。

### 3.2 构建阶段

阶段是稳定的产品构建顺序，不声称同阶段自动并行：

```text
Stage 0  hexagonrpc  libssc  linux-firmware-sheng  linux-xiaomi-sheng
Stage 1  iio-sensor-proxy
Stage 2  xiaomi-sheng-rfsa  xiaomi-sheng-sensors
Stage 3  其余设备集成包
```

内部依赖单独声明：

```text
hexagonrpc ──────────────────────────► xiaomi-sheng-sensors
   └────────────────────────────────► xiaomi-sheng-rfsa
libssc ─────► iio-sensor-proxy ─────► xiaomi-sheng-sensors
   └────────────────────────────────► xiaomi-sheng-thp
```

依赖包通过 `makechrootpkg -I` 注入 clean chroot。局部构建不清空 `out/pkgs`，使
`--stage` 和 `--from` 可以复用已有依赖；一个包只有在成功生成新产物后才替换自己
的旧产物。

### 3.3 pacman 仓库

`build-repo.sh` 在 `out/.repo.*` 中生成完整暂存仓库，成功后整体替换 `out/repo`，
避免旧数据库与新包文件处于半更新状态。`out/sheng-repo.conf` 是给宿主使用的路径；
rootfs 不复制该路径，而是在镜像内生成 `file:///opt/sheng-repo` 配置。

### 3.4 Rootfs

`mkrootfs.sh` 的顺序如下：

1. 创建稀疏 ext4 镜像并 loop mount；
2. pacstrap 基础用户态，不安装通用 `linux-aarch64`/`linux-firmware`；
3. 把 `out/repo` 复制到镜像 `/opt/sheng-repo`；
4. 在 chroot 内一次安装清单中的 16 个设备包；
5. 安装可选桌面和额外包，配置 locale、用户、网络；
6. 创建 `/boot/loader/entries/arch.conf`；
7. 生成 initramfs 和 boot.img；mkinitcpio post hook 在结构上只负责构建；
8. 导出 boot.img、卸载并用 e2fsck 验证 rootfs。

包事务期间将 `MKINITCPIO_POST_HOOKS` 指向空位置，避免尚未生成 boot entry 时执行
post hook。最后一次 mkinitcpio 只生成镜像；裸分区写入只存在于必须人工调用、单槽、
先备份后校验的 `sheng-boot-slot` 中。

## 4. 运行时机理

### 4.1 FastRPC 与传感器

```text
Linux fastrpc driver
       │ 创建 /dev/fastrpc-adsp
       ▼
60-hexagonrpc.rules
       │ 只设置 owner/group/mode
       │
       │ 管理员或明确的消费者按需启动
       ▼
hexagonrpcd-adsp-sensorspd.service
       │ reverse RPC / HexagonFS
       ▼
/usr/share/qcom/sm8550/Xiaomi/sheng
       │
       ├─ DSP shared objects / Android path mappings
       └─ sensor config + registry
                         │
                         ▼
                    libssc
                         │
                         ▼
                 iio-sensor-proxy
                         │ D-Bus
                         ▼
              desktop and device helpers
```

HexagonRPC 0.6.0 使用 Rust workspace：`hexagonrpc-sys` 提供内核 UAPI，
`hexagonrpc` 实现用户态 FastRPC，`hexagonrpcd` 提供反向隧道和 HexagonFS，
`sns-registrygen` 生成传感器注册表。包内 systemd 服务以非特权 `hexagonrpc` 用户
运行，udev 设置 FastRPC 与 DMA heap 权限，但不通过 `SYSTEMD_WANTS` 启动服务。
这条链路是可选的 Android 传感器兼容层，不属于内核设备初始化。

ADSP 的 FastRPC rpmsg 节点通过 DTB `memory-region` 绑定 16 MiB、4 MiB
对齐且位于 4 GiB 以下的可复用 `shared-dma-pool`。它只服务于明确启动的 FastRPC
remote heap，避免较大连续分配从已碎片化的通用 DMA zone 中直接回收/compact；
它不是 ALSA/ASoC 音频修复。任何静态 PD 都必须在确认内核日志显示 FastRPC 已获得
专用 reserved DMA memory 后再单独验证。

### 4.2 主线音频链路

```text
qcom_q6v5_pas/remoteproc ──► 签名 ADSP firmware
                                    │ GLink channel: adsp_apps
                                    ▼
                              GPR ──► Q6APM/APM
                                    │
                  PCM/DAI graph ◄───┴───► LPASS/SoundWire
                         │                      │
                         ▼                      ▼
                    ALSA/ASoC card      WCD938x + CS35L43
                         │
                         ▼
                       UCM2
```

GPR 是 AP 与 QDSP 音频/语音服务的内核 IPC；Q6APM 作为 GPR service 提供 DSP
audio ports。声卡枚举不调用 FastRPC，也不需要 `hexagonrpcd-adsp-audiopd`。
Android 提取的 `adsp.mbn`、codec DSP 固件及必要校准仍可作为外部 firmware 使用，
但固件来源和内核控制路径必须分层。RFSA `.so` 仅在实际 DSP graph/算法请求外部库且
受控测试证明需要时，才通过手动 FastRPC listener 提供。

### 4.3 其他设备集成

| 子系统 | 接入方式 |
|---|---|
| 音频 | remoteproc + GPR/Q6APM + LPASS/SoundWire + ASoC；UCM2 只选择用户态 route |
| 触控与笔 | `xiaomi-sheng-thp` 读取内核 proc 接口，并使用 libssc 姿态数据 |
| 键盘 | devauth 通过 QTEE 认证；helper 直接读取内核 `nanosic_hinge` ABI |
| 指纹 | 私有 libfprint backend + qteesupplicant + fprintd drop-in |
| 充电 | power_supply/typec udev 事件触发 MiPPS；charger mode 由 cmdline 条件启动 |
| 启动 | mkinitcpio 生成 initramfs，post hook 组合 kernel/initramfs/DTB 为 boot.img |

### 4.4 启动固件边界

Linux 的近期目标是从 ABL 直接加载 `boot.img + DTB` 迁移到 `Mu UEFI + 完整 DTB`。
面向 Windows 的 `UEFI + ACPI` 是独立硬件描述路径，不能用不完整 DSDT 替代 Linux DT。
详细的槽位保护、内存图验证和分区约束见 `docs/BOOT-UEFI.md`。

## 5. HexagonRPC 更新策略

上游提交 `db659bdd117337766846bb6804a4453b6db06925` 将 C/Meson 实现整体迁移到
Rust/Cargo，并将部署服务从旧 `adsprpcd_*` 命名迁移为 `hexagonrpcd-*`。

本仓库采取以下适配：

- 源码锁定完整 commit；版本标记为 `0.6.0.r241.gdb659bd`；
- 使用 `Cargo.lock`，`cargo fetch --locked` 后以 `--frozen` 构建和测试；
- 安装 `hexagonrpcd`、`hexagonrpc-probe`、`sns-registrygen`、udev/sysusers/systemd/man/docs；
- udev 只设置权限，不自动启动 ADSP/CDSP listener；
- 键盘 helper 不依赖 HexagonRPC，直接使用内核 `nanosic_hinge` ABI；
- 不保留已由上游提供的本地 HexagonRPC service override。

上游仓库当前没有 `v0.6.0` tag，因此不能直接采用其引用该 tag 的示例 PKGBUILD。
将来上游发布 tag 后，可切换为 tag archive 和固定内容校验和。

## 6. 验证策略

`make check` 不访问网络，也不需要 root：

- 对脚本执行 `bash -n`；安装了 shellcheck 时进一步静态检查；
- 比较包清单、构建阶段和实际 PKGBUILD 目录；
- 检查本地文件包确实引用 `files.tar.gz`；
- 用 `makepkg --printsrcinfo` 验证 16 个 PKGBUILD 元数据。

完整验证分层进行：

1. `make check`；
2. 重复运行 `make files` 并比较哈希；
3. 单独构建 `hexagonrpc`，执行其 Cargo workspace tests；
4. clean chroot 构建全部包；
5. rootfs 构建与 e2fsck；
6. 真机验证 FastRPC、传感器、触控、音频和 A/B 启动。

CI 只执行第 1 层。涉及 aarch64、sudo、loop mount、设备节点或实际分区写入的测试
必须在受控环境中完成。
