# files/ 集中化管理 + 预处理规范化设计

## 1. 动机

- 消除对 `ianchb/debian-sheng` 的运行时依赖
- 所有本地维护的文件统一在 `files/{direct,install}/` 下管理，不再散落在 `pkgs/` 下
- 所有 PKGBUILD 中的 sed 替换/路径修正等预处理操作提前应用到文件本身，PKGBUILD 只负责安装

## 2. files/ 目录结构

```
files/
├── direct/                              # 直接拷贝的数据文件（cp -r）
│   ├── alsa-ucm-xiaomi-sheng/
│   │   └── usr/share/alsa/ucm2/
│   │       ├── Xiaomi/sheng/
│   │       │   ├── HiFi.conf
│   │       │   └── Xiaomi-Pad6SPro.conf
│   │       └── conf.d/sm8550/
│   │           └── Xiaomi-Pad6SPro.conf   → ../../Xiaomi/sheng/Xiaomi-Pad6SPro.conf
│   └── xiaomi-sheng-sensors/
│       └── usr/share/qcom/               # 传感器配置数据
│           ├── conf.d/sheng.yaml
│           └── sm8550/Xiaomi/sheng/
│               ├── config/               # *.json 传感器配置
│               ├── registry/             # 传感器注册表
│               ├── socinfo/              # SoC 信息
│               └── sns_reg_version
├── install/                             # 需要安装的系统集成文件（install -Dm644）
│   ├── hexagonrpc/
│   │   └── adsprpcd_sensorspd.service    # systemd 单元文件（含 qteesupplicant 依赖）
│   ├── xiaomi-mipps-auth/
│   │   ├── xiaomi-mipps-auth.service     # sed 已预应用
│   │   └── 90-xiaomi-mipps-auth.rules    # 同上
│   ├── xiaomi-sheng-keyboard-helper/
│   │   ├── xiaomi-sheng-keyboard-helper-angle.service
│   │   └── xiaomi-sheng-keyboard-helper-micmute.service
│   ├── xiaomi-sheng-thp/
│   │   └── xiaomi-sheng-thp.service
│   ├── xiaomi-sheng-fingerprint/
│   │   ├── sfsconfig.service
│   │   ├── qteesupplicant.service
│   │   ├── 10-xiaomi-sheng-fpc1553.conf
│   │   └── 99-qcomtee-fpc.rules
│   ├── xiaomi-sheng-devauth/
│   │   └── xiaomi-sheng-devauth.service         # 含 qtee.conf 合并的依赖
│   └── xiaomi-sheng-sensors/
│       └── 81-sheng-ssc-sensors.rules
```

## 3. 文件分类

| 类别 | 子目录 | 内容 | 处理方式 |
|------|--------|------|----------|
| **direct/** | 无 | sensor configs, ALSA UCM | `cp -dr` 直接拷贝 |
| **install/** | systemd/ | .service 文件（已预应用路径修正） | `install -Dm644` |
| | udev/ | .rules 文件 | `install -Dm644` |

> libssc 的 `wait_for_qmi_service.patch` 已移除（上游已修复，不再需要）。

## 4. package-files.sh

**作用**：将 `files/{direct,install}/<pkg>/` 合并打包为 `pkgs/<pkg>/files.tar.gz`。

```bash
#!/bin/bash
# 遍历 files/{direct,install}/ 下每个子目录，合并打包到对应 pkgs/<pkg>/
# 见 scripts/package-files.sh
```

**在 Makefile 中作为 fetch 阶段的新命令**：

```makefile
fetch:
	@bash scripts/package-files.sh
```

## 5. PKGBUILD 改动要点

| 包名 | 当前 source | 修改后 source | package() 变化 |
|------|-------------|---------------|----------------|
| fastrpc→hexagonrpc | `files.tar.gz` (含 service) | 不变 | 不变（service 仍在解压目录根下） |
| libssc | — | — | **删除 prepare()**，patch 不再需要 |
| xiaomi-sheng-sensors | `files.tar.gz` | 不变 | 将 `usr/` 整体 `cp -r` 拆为 `usr/share/` 直接拷贝 + `lib/` 用 `install -Dm644` |
| xiaomi-mipps-auth | `files.tar.gz` | 不变 | 不变 |
| xiaomi-sheng-keyboard-helper | `files.tar.gz` | 不变 | 不变 |
| xiaomi-sheng-thp | `files.tar.gz` | 不变 | 不变 |
| xiaomi-sheng-fingerprint | `files.tar.gz` | 不变 | 不变 |
| alsa-ucm-xiaomi-sheng | `files.tar.gz` | 不变 | 不变 |
| xiaomi-sheng-devauth | `files.tar.gz` | 不变 | 不变 |

## 6. 新增 alsa-ucm-xiaomi-sheng 包

```bash
# Maintainer: Jacobi Lie <jssnlzxcr@gmail.com>
pkgname=alsa-ucm-xiaomi-sheng
pkgver=1.0
pkgrel=1
pkgdesc="ALSA UCM configuration for Xiaomi Pad 6S Pro 12.4 (sheng)"
arch=('aarch64')
url="https://github.com/ianchb/debian-sheng"
license=('custom')
depends=('alsa-ucm-conf')
source=("files.tar.gz")
sha256sums=('SKIP')

package() {
  cd "${srcdir}"
  install -d "${pkgdir}/usr"
  cp -r usr/* "${pkgdir}/usr/"
}
```

## 7. docs/preprocessing.md

记录每个 `files/{direct,install}/<pkg>/` 中文件相对于上游原始文件所做的预处理操作。

## 8. 移出的文件

- `scripts/fetch-sources.sh` — 不再需要
- `pkgs/hexagonrpc/adsprpcd_sensorspd.service` — 移至 `files/install/hexagonrpc/`
- `pkgs/libssc/wait_for_qmi_service.patch` — **移除**（上游已修复）
- `pkgs/xiaomi-sheng-sensors/sheng-sensors-files.tar.gz` — 改为从 `files/{direct,install}/xiaomi-sheng-sensors/` 打包
- `pkgs/xiaomi-sheng-sensors/sheng-sensors-files/` — 移至 `files/{direct,install}/xiaomi-sheng-sensors/`
