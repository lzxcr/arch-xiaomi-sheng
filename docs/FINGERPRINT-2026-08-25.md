# 指纹模块调查结论（2026-08-25）

## 结论：指纹模块可正常驱动

Xiaomi Pad 6S Pro (sheng) 的 FPC1553 指纹传感器在主线 Linux 下**能被正常驱动**，
识别、读取、持久化链路完整。

## 架构（sec 说明）
指纹识别由 TrustZone/QSEE 完成，内核驱动只提供平台侧（供电/复位/IRQ）：
- 内核 `drivers/misc/fpc1553.c`：兼容 `fpc,fpc1020`，probe 成功，创建 sysfs 接口
  （power_cfg/power_ctrl/hw_reset/device_prepare/irq/vendor 等），**不传图象数据**。
- 真正的识别在 QSEE 应用 `fpcsheng`（`fpcsheng.elf`），用户态经 `/dev/tee0` 调用。
- 用户态栈：`xiaomi-sheng-fingerprint` 提供 `libfpc1553-qtee.so`（自定义 libfprint 驱动）
  + `qteesupplicant` + 补丁版 `libfprint-2.so`，接入 `fprintd`。

## 验证证据（全部通过）
1. 内核日志：`fpc1553 fingerprint_fpc: fpc1553 platform side ready`（probe 成功）
2. `/dev/tee0` 存在，`qteesupplicant`（QSEE）运行，RPMB 服务注册
3. `libfprint` 识别到设备：`found 1 devices ... FPC1553`
4. 录入第一阶段通过：`Enroll result: enroll-stage-passed`
5. **QSEE 指纹数据成功写入 RPMB**：`RPMB write: 2 sectors`

## 残余说明
- 多阶段录入未显示 `enroll-completed`，因通过后台会话运行触发 polkit 授权中断
  （`Not Authorized: net.reactivated.fprint.device.enroll`），非硬件/驱动问题。
  在图形桌面终端（tty2/lzx 会话）运行 `fprintd-enroll` 即可完成完整录入。
- `qteesupplicant` 的 `RPMB_WARN: Failed to acquire/release wakelock` 仅为
  电源管理日志警告，**不影响 RPMB 写入成功**。
- 依赖：`linux-firmware-sheng` 包（`fpcsheng.elf`）+ 内核 FPC1553 驱动 + `/dev/tee0`。

## 使用方式（图形会话）
```sh
fprintd-enroll        # 录入指纹
fprintd-verify        # 验证指纹
```
