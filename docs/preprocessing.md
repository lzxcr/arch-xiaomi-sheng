# 预处理操作记录

每个 `files/<pkg>/` 中的文件相对于上游原始文件所做的预处理操作记录。所有预处理已在文件提交前完成，`files/` 下不再包含 `preprocess.sh` 脚本。

---

## fastrpc

| 上游来源 | 预处理操作 |
|----------|-----------|
| `ianchb/debian-sheng` / `patches/adsprpcd-sensorspd.service` | 无（直接复制） |

---

## xiaomi-sheng-sensors

| 上游来源 | 预处理操作 |
|----------|-----------|
| `ianchb/debian-sheng` / `sheng-sensors-files/` | 移除 `usr/lib/systemd/` 目录 |

说明：从 debian-sheng 复制传感器配置文件，按 PKGBUILD 规则移除 systemd 单元目录。

---

## alsa-ucm-xiaomi-sheng

| 上游来源 | 预处理操作 |
|----------|-----------|
| `ianchb/debian-sheng` / `usr/share/alsa/ucm2/` | `conf.d/sm8550/Xiaomi-Pad6SPro.conf` 转为指向 `../../Xiaomi/sheng/Xiaomi-Pad6SPro.conf` 的符号链接 |

说明：ALSA UCM2 配置文件直接取自 debian-sheng。`conf.d/` 下的文件原本是独立副本，改为符号链接以避免重复。

---

## xiaomi-mipps-auth

| 上游来源 | 版本 | 文件 | 预处理 |
|----------|------|------|--------|
| `ianchb/xiaomi-mipps-auth` | v0.21 | `xiaomi-mipps-auth.service` | `/usr/libexec/` → `/usr/lib/xiaomi-mipps-auth/` |
| | | `90-xiaomi-mipps-auth.rules` | 同上 |

---

## xiaomi-sheng-keyboard-helper

| 上游来源 | 版本 | 文件 | 预处理 |
|----------|------|------|--------|
| `ianchb/xiaomi-sheng-keyboard-helper` | v0.2.0 | `systemd/*.service` | `/usr/libexec/` → `/usr/lib/xiaomi-sheng-keyboard-helper/` |
| | | `systemd-user/*.service` | 同上 |

---

## xiaomi-sheng-thp

| 上游来源 | 版本 | 文件 | 预处理 |
|----------|------|------|--------|
| `ianchb/xiaomi-sheng-thp` | v0.3.6 | `systemd/xiaomi-sheng-thp.service` | `/usr/libexec/xiaomi-sheng-thp/xiaomi-sheng-thp` → `/usr/lib/xiaomi-sheng-thp/xiaomi-sheng-thp` |

---

## xiaomi-sheng-fingerprint

| 上游来源 | 版本 | 文件 | 预处理 |
|----------|------|------|--------|
| `ianchb/xiaomi-sheng-fingerprint` | v0.1.4 | `systemd/sfsconfig.service` | `/usr/libexec` → `/usr/lib/xiaomi-sheng-fingerprint` |
| | | `systemd/qteesupplicant.service` | ① `/usr/libexec` → `/usr/lib/xiaomi-sheng-fingerprint` |
| | | | ② `/usr/lib/aarch64-linux-gnu/qtee-listeners` → `/usr/lib/qtee-listeners` |
| | | `systemd/fprintd.service.d/10-xiaomi-sheng-fpc1553.conf` | 无 |
| | | `udev/99-qcomtee-fpc.rules` | 无 |

---

## libssc

`wait_for_qmi_service.patch` 已移除 — 上游（libssc v0.4.4）已修复 QMI 服务等待逻辑，不再需要补丁。
