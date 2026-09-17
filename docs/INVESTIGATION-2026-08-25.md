# Sheng 硬件调查记录（2026-08-25 会话）

本文件记录对 Xiaomi Pad 6S Pro (sheng) 的四项调查结论，供后续维护参考。
所有检查均只读（除注明外），未刷写启动槽、未重启、未重分区。

---

## 1. 触控笔（Focus Pen Pro / P81c）失效 — 根因

### 结论
笔输入失效的根因**不在 THP 解码，不在刷新率，不在模式选择，也不在蓝牙本身**，
而是在**充电座与笔之间的通信链路未建立**，导致 `qcom_battmgr` 读到的笔属性
全部是无笔默认值，进而无法自动蓝牙配对，THP 无法识别笔模型。

### 关键证据
- **笔属性恒为"无笔"默认值**（`/sys/devices/platform/pmic-glink/pmic_glink.power-supply.0/xiaomi/`）：
  - `pen_hall3/4 = 1/1`（ANDRoid 语义：`!(1&&1)=0` = 笔未放好/未连接）
  - `pen_mac_l/h = 0`（无 MAC → 无法蓝牙配对）
  - `pen_soc = 255`（无电量）
  - `tx_iout = 0`、`pen_tx_ss = 0`（无线充电 TX 未工作）
- 对照：`bq2597x_chip_ok=1`、`bq2597x_bus_voltage=1481`、`authentic=1` ——
  **qcom_battmgr 读取机制本身正常**，笔属性读到的确实是"无笔"状态。
- 无线充电电源 `qcom-battmgr-wls`：`online=0`、`current_now=0` —— **无线充电 TX 未激活**。
- 手动写 `fake_ss=1`（笔传感器开关，主线唯一可写 pen 属性）→ **笔属性无任何变化**。

### 缺失的控制链路
Android 依赖一条主线完全缺失的链路：
```
笔放充电槽 → Android 充电服务 → micharge HAL 写 wls_tx_speed/bt_state/reverse_chg_mode
           → PMIC 启动无线充电 TX → 与笔通信 → 读 pen_mac/pen_soc → 蓝牙自动配对
```
- 主线 `qcom_battmgr.c` **只有**笔属性的**只读**接口（`XM_BATT_PEN_*` 0x53-0x5c），
  **没有** `WLS_START`/`bt_state`/`wls_tx_speed`/`reverse_chg_mode` 等**控制**接口。
- 主线也**没有** Android 的充电服务（micharge HAL）来触发通信。
- `ianchb` 的 kernel commit（`5097314a0c`、`000c6607f7`）只做了**只读暴露**，
  注释明示"hall values identify whether stylus is docked"，即假设 PMIC 固件
  会自动填充——但本机上这些值是空的。

### 否定的假设（均已排除）
- **非 144Hz/120Hz 刷新率问题**：正确采样（读 32B StreamHeader + 5417B 帧记录）
  在 120Hz、144Hz 下所读帧全部 `dt=3`（普通触摸帧），无 `0x1d` 笔帧。
- **非 THP 解码问题**：THP 服务运行正常（touch 工作、无崩溃），它对真实触摸帧
  处理正确。用 THP 真实解码器处理捕获帧时 `active=1`（此为单帧测试）。
- **非蓝牙坐标依赖**：笔的坐标/倾斜/悬停由 THP 控制器直接检测，不依赖蓝牙；
  蓝牙仅用于压力 HID 与 posture。
- **非 fpcsheng.elf**：那是 FPC 指纹固件（`compatible = "fpc,fpc1020"`），与笔无关。
- **非 libssc**：libssc 主要服务 Focus Pen Pro 的 posture 传感器路径。

### 重要更正
调查初期因**帧边界读取错误**（把 32 字节 `nvt_thp_stream_header` 当帧开头），
曾误判"固件检测到笔接触"。后改用内核真实记录格式（`STREAM_HEADER(32) + FRAME(5417)=5449`
字节）重新采样，确认所有记录 `dt=3`，无笔帧。此前的相关结论应视为无效。

### 修复方向（尚未实施）
在内核 `qcom_battmgr.c` 补上笔通信控制接口 + 编写用户态触发服务。需先从 sheng
的 PMIC 固件确认这些控制属性的传输号（主线属性号与 Android marble 设备不同）。
风险较高，建议作为独立内核开发任务。

---

## 2. 音频链路驱动方式 — 已确认规范

### 结论
音频完全由**内核主线方式**驱动，功能正常（`paplay` 实测通过）。

### 链路
```
remoteproc0 加载 qcom/sm8550/sheng/adsp.mbn (38MB)
→ adsp is now up
→ qcom,apr 注册 APR/GPR (APM service 2:1/2:2)
→ snd-sc8280xp ASoC 声卡 (XiaomiPad6SPro) 绑定
→ tplg: qcom/sm8550/Xiaomi-Pad6SPro-tplg.bin
→ CS35L43 扬声器放大器 + wsa_macro/va_macro + SoundWire
```
- ALSA 卡：`0 [XiaomiPad6SPro]`，4 个 PCM（3 playback + 1 capture）
- PipeWire sinks：Speaker/Headphones/HDMI 均存在
- 实测：`paplay` 播放 880Hz 音调成功（exit 0）

### 固件来源
- `adsp.mbn`/`cdsp.mbn`：来自 `github.com/ianchb/sheng-firmware`（锁定 commit
  `2c1e2729...`），Android 提取固件。与 ROM modem 镜像的 `adsp.mbn` 哈希不同
  （均是 Qualcomm DSP6 ELF，来源镜像/分区不同）。
- `Xiaomi-Pad6SPro-tplg.bin`：ASoC 拓扑，主线构建。
- 音频 DSP 动态库（`dsp/adsp/*.so`）：来自 ROM dsp 分区。

### 注意事项
- 启动日志有一条 `qcom-apm CMD timeout for [1001021]` 警告，但**未影响音频**（播放正常）。
- 当前内核仍报 `no reserved DMA memory for FASTRPC`（FastRPC 遗留，DTB 已修复但
  **当前运行内核未生效**，需刷 boot 重启后验证；与音频链路无关）。

---

## 3. 启动日志问题分类

### 待修复的内核级问题
1. **GPI DMA / SPI 超时**（`NVT-ts-spi spi0.0: SPI transfer timed out` +
   `gpi CH STOP completion timeout`）—— 每约 6.5 分钟一次，发生在 THP 触摸帧
   SPI 传输停止时。GPI `CMD_TIMEOUT_MS=250`，通道活跃时停止会超时。伴随
   THP `stream_drops` 高（本机约 48% 帧丢失）。
2. **DRM vblank 超时**（`dpu error: vblank timeout 400000`）—— 偶发，需关注，
   可能与刷新率时序相关。
3. **FastRPC reserved DMA** —— DTB 已修复（16MiB shared-dma-pool + memory-region），
   但当前运行内核未带该 DTB（A 槽 boot.img 已生成待刷，需重启验证）。

### 已就绪的内核补丁（未提交 / 未生效）
`files/install/linux-xiaomi-sheng/` 下已有：
- `0001-ucsi-make-pmic-glink-reregistration-safe.patch`（UCSI 竞态）
- `0002-soundwire-qcom-handle-wake-pm-errors.patch`（SoundWire IRQ 负 errno）
- `0003-ath12k-read-standard-firmware-mac-address.patch`（WiFi MAC）
- `0004-arm64-dts-qcom-sheng-drop-placeholder-bd-address.patch`（BT 占位符）
- `nanosic-wn8030-async-auth.patch`（键盘异步认证）
- `fastrpc-reserved-memory.dtso` / `sm8550-xiaomi-sheng-fastrpc-memory.patch`

这些需集成进 `linux-xiaomi-sheng` PKGBUILD、随新内核生效（需刷 boot + 重启）。

### 无害/用户态告警
- `libinput: kernel bug: missing right button`（触控板，无害）
- `plasmashell: dragHelper is not defined`（AndromedaLauncher 组件 QML，无害）
- `portal: RTKit/RealtimeKit service unknown`（xa-deskportal，功能不受影响）

---

## 4. UEFI 本地构建可行性 — 可行但需补工具

### 结论
**本机（aarch64 Linux）本地构建 UEFI 在架构层面可行**——`build_uefi.py` 的
`is_system_supported()` 只检查 `os.name == "posix"`，**不限制 x86_64**。

### 现状
- 设备：`mu_aloha_platforms/Platforms/KailuaPkg/Device/xiaomi-sheng`（SM8550 / KailuaPkg）
- 构建配置：`build_cfg/sm8550.json`
- 入口：`build_uefi.py -d xiaomi-sheng`（需 `LINUX_DTB` 指向匹配的 `sm8550-xiaomi-sheng.dtb`）
- DTB 真实文件已具备：`/boot/sm8550-xiaomi-sheng.dtb`（140KB，非 dummy）及内核源码 DTS

### 硬性前提（README 明确）
- `linux-sheng.dtb`（DeviceTreeBlob/Linux/）仍是 6 字节 placeholder，**构建已拒绝**
  直接用它；必须用 `LINUX_DTB=/path/to/sm8550-xiaomi-sheng.dtb` 指定真实 DTB。
- UEFI 内存图与 Linux reserved-memory 节点必须一致（ADSP/LPASS、CDSP、video、ramoops、
  CMA、FastRPC shared DMA）。
- ACPI（`DSDT.aml`）仍不完整，sheng 仅宜走 "UEFI + DT" 路径；Windows/ACPI 为独立后续。

### 缺失的工具（Arch 用 pacman 补齐）
`clang llvm lld nasm iasl mono uuid-dev`，以及 `gcc-aarch64-linux-gnu`（交叉编译器，
但本机是 aarch64 可免除或仍安装）+ nuget（经 mono）。

### 安全测试序列（照抄 README）
1. 保留当前可启动槽为回退槽。
2. 校验 DTB magic/size/compatible/reserved-memory。
3. 用 `LINUX_DTB` 显式构建 UEFI Android boot image。
4. 备份并仅写非活动槽。
5. 仅测试单次启动，外部恢复手段就绪。
6. 对比 EFI/DT/内存图/remoteproc/ALSA/FastRPC 日志后再决定默认 UEFI。

---

## 附：尚未完成 / 待用户决策项
- 笔感知修复（需内核补控制接口，独立开发任务）。
- 启动日志内核补丁集成进 PKGBUILD + 刷 boot 重启验证（已授权范围外，需用户指示）。
- 音频 FastRPC reserved DMA 验证需新 DTB 生效后。

---

## 补记 (2026-08-25 21:03) — 已修复的启动日志相关 BUG

### PKGBUILD 蓝牙占位符移除失效 (已修复)
`pkgs/linux-xiaomi-sheng/PKGBUILD` 原用 `if fdtget ... local-bd-address &>/dev/null`
探测属性存在性。但 `fdtget` 对 `local-bd-address`(byte 数组) 读取**恒返回 exit=1**
(即使属性存在，报 `FDT_ERR_NOTFOUND`)，导致条件永假、`fdtput -d` 删除被跳过，
BT 占位符一直残留在 DTB 里。

修复：改用 `dtc -I dtb -O dts ... | grep -q local-bd-address` 可靠探测，
并用 `fdtput -d ... || true` 容忍幂等错误。

验证：
- `makepkg` 完整构建成功 (`linux-xiaomi-sheng 7.2.0-4`)
- 包内 DTB 已无 `local-bd-address` (原 `[24 00 00 00 5a ad]`)
- 包内 DTB 保留 FastRPC `memory-region` (15a phandle)
- 6 个源码补丁正确安装到 `/usr/share/doc/linux-xiaomi-sheng/`

注：6 个源码级补丁 (UCSI/SoundWire/ath12k MAC/异步认证) 针对 ianchb sm8550-mainline
**源码**，均对 7.2.0 tag 干净可应用，但当前 `.deb` 预编译流程无法应用它们 —— 这些
修复需切换到源码构建内核才会真正生效（本次验证为 DTB 级修复已落地）。
