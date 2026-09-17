# Sheng 启动、UEFI 与分区策略

本文记录 Xiaomi Pad 6S Pro 12.4（sheng）当前真机状态和迁移约束。所有检查默认只读；
刷写启动槽、切槽、修改 GPT 或重启必须是独立且明确批准的操作。

## 当前结论

- 当前 Linux 由 Android ABL 解析 `boot.img` 后直接交接，`/sys/firmware/efi` 与
  `/sys/firmware/acpi` 均不存在；内核虽然启用了 EFI/ACPI，却没有收到相应固件交接。
- `androidboot.vbmeta.device` 的 PARTUUID 对应 `vbmeta_b`，因此当前活动槽是 B。
- `boot_a`、`boot_b` 都是 192 MiB。B 槽应继续作为已知可启动的回退槽，A 槽才是
  后续 Linux DTB 或 UEFI 的试验槽。
- 6 个 UFS LUN 的主/备 GPT 均通过 `sfdisk --verify`。`sde77 last_parti` 的类型
  GUID 全零、长度为零，是未使用的 Qualcomm 哨兵项，不是有效分区或损坏。
- 用户 LUN 已有 512 MiB ESP，迁移 UEFI 不需要再创建 ESP。当前 `super` 只有
  7.8 MiB，不能承载完整 Android 动态分区或 OTA。
- 目前不建议重分区。除非确定要恢复 Android，并准备好离线缩容、全盘备份和可用的
  原厂 fastboot/rawprogram 分区资料，否则修改 GPT 只会增加不可恢复风险。

运行以下命令可重复获得只读报告：

```bash
make audit-device
sudo make audit-device  # 额外执行每个 UFS LUN 的 sfdisk --verify
```

## 三种启动契约

| 路径 | 固件交接 | Linux 硬件描述 | 当前适用性 |
|---|---|---|---|
| ABL 直接启动 | ABL 解析 Android `boot.img` 并跳转内核 | `boot.img` 内完整 sheng DTB | 当前已知可用基线 |
| Mu UEFI + DT | ABL 将 Mu/BootShim 当作内核载入，Mu 提供 EFI 服务 | Mu 固件卷内完整、与内核匹配的 sheng DTB | Linux 的目标迁移路径 |
| Mu UEFI + ACPI | 同上 | 由 UEFI 提供完整 ACPI 表 | 面向 Windows 的长期独立路径 |

Arm64 Linux 在一次启动中选择 DT 或 ACPI，而不是把两者随意混用。Sheng 上大量
Qualcomm remoteproc、LPASS/ASoC、FastRPC、pinctrl 和电源域驱动目前以 DT 为成熟契约，
所以先迁移到“UEFI + DT”更符合主线 Linux 的现实。ACPI 应保留给 Windows 与后续
Linux 实验，但必须维护可审阅的 ASL 源码，不能把一份不完整的二进制 DSDT 当作完成。

## UEFI 下音频缺失的根因

`mu_aloha_platforms` 的 sheng `linux-sheng.dtb` 原先只有 `dummy` 六个字节；项目清单
同时把 sheng DSDT 标为不支持。直接启动时，ABL 使用的是完整 Linux DTB，其中包含
声卡、codec、SoundWire、LPASS/ADSP remoteproc、固件 carveout 与 FastRPC。UEFI 路径
没有提供等价描述，因此音频、DSP 乃至其他设备缺失是必然结果，而不是 ALSA UCM
单点故障。

此外还必须验证 UEFI `PlatformMemoryMapLib` 与 Linux `reserved-memory` 完全不冲突。
ADSP/LPASS、CDSP、视频、CMA 和 FastRPC DMA pool 若被 UEFI 错误声明为普通内存或在
`ExitBootServices()` 后仍被占用，会造成 remoteproc 启动失败、DMA 分配风暴或死机。

UEFI 工程现在会拒绝用 dummy/非法 DTB 构建 sheng，并允许显式传入内核构建产物：

```bash
cd ../mu_aloha_platforms
LINUX_DTB=/path/to/sm8550-xiaomi-sheng.dtb \
  ./build_uefi.py -d xiaomi-sheng
```

## 分阶段迁移门槛

1. 固定直启基线：保存完整 `dmesg`、`/proc/iomem`、live DT、ALSA、remoteproc、
   FastRPC 和固件加载结果。
2. DT 一致性：UEFI 嵌入与目标内核完全匹配的 DTB，并验证 `compatible`、全部
   reserved-memory、FastRPC pool 和音频拓扑。
3. 单槽试验：保留活动 B，只备份并写 A；外部 fastboot/recovery 必须可用。
4. UEFI 启动验证：确认 EFI runtime、ESP、内存图、设备树和 initramfs，再比较 ADSP、
   ALSA、视频 DSP 与直接启动基线。
5. 通过多次冷启动、挂起恢复和 DSP 错误恢复后，才考虑把 UEFI 设为默认。
6. 最后才开展 ACPI/Windows：从可版本控制的 ASL 生成 AML，并逐设备补齐 Windows
   驱动、资源与电源描述。

生成 boot.img 不会写分区：

```bash
sudo mkinitcpio -p linux-xiaomi-sheng
sudo sheng-boot-slot status
sudo sheng-boot-slot install --slot a --image /boot/boot.img
```

`sheng-boot-slot` 默认拒绝活动槽；它先备份完整目标分区，再写入并校验。它从不提供
“同时写 A/B”的选项。恢复同样必须指定单槽和完整备份。

## Qualcomm/GPT 约束

标准 EDK2 GPT 驱动会校验 header、partition-entry array 的 CRC、边界与重叠关系。
Qualcomm 固件还会在特定 UFS LUN 中按名称、类型 GUID、分区 GUID 和 A/B 属性查找
`xbl`、`abl`、`vbmeta`、`dtbo`、安全存储及固件分区；本地 `SecParti.cfg` 也明确按
GUID 搜索跨 LUN 的安全存储。

没有证据表明它要求用户 LUN 的每个起始扇区和容量与出厂布局完全相同：当前设备的
用户 LUN 已经明显修改但仍能启动。合理边界是：保持 GPT 合法，绝不移动/删除 sdb–sdf
上的启动、安全与校准分区，保持关键名称/GUID/LUN/属性；不要把“系统还能启动”误当成
可随意修改 GPT 的保证。

官方 OTA `payload.bin` 只含分区镜像，不等同于完整 GPT/Firehose/rawprogram 恢复包。
在获得匹配机型的完整恢复资料和当前 GPT 原始备份前，不应实施分区重建。

## 上游规范依据

- [Linux arm64 ACPI](https://www.kernel.org/doc/html/latest/arch/arm64/arm-acpi.html)
- [Devicetree DTS coding style](https://docs.kernel.org/devicetree/bindings/dts-coding-style.html)
- [Qualcomm FastRPC binding](https://www.kernel.org/doc/Documentation/devicetree/bindings/misc/qcom,fastrpc.yaml)
- [AOSP dynamic partitions](https://source.android.com/docs/core/ota/dynamic_partitions/implement)
- [AOSP super sizing](https://source.android.com/docs/core/ota/dynamic_partitions/how_to_size_super)
- [Windows UEFI requirements](https://learn.microsoft.com/windows-hardware/drivers/bringup/uefi-requirements-that-apply-to-all-windows-platforms)
