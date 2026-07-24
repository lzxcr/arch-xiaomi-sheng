# files/ 集中化管理 + 预处理规范化设计

## 1. 动机

- 消除对 `ianchb/debian-sheng` 的运行时依赖
- 所有本地维护的文件统一在 `files/` 下管理，不再散落在 `pkgs/` 下
- 所有 PKGBUILD 中的 sed 替换/路径修正等预处理操作提前应用到文件本身，PKGBUILD 只负责安装

## 2. files/ 目录结构

```
files/
├── fastrpc/
│   └── adsprpcd-sensorspd.service      # systemd 单元文件
├── xiaomi-sheng-sensors/
│   └── usr/                             # 278 个传感器配置文件
│       ├── lib/systemd/system/iio-sensor-proxy.service.d/
│       │   └── 10-sheng-sensors.conf
│       ├── lib/udev/rules.d/
│       │   └── 81-sheng-ssc-sensors.rules
│       └── share/qcom/...
├── xiaomi-mipps-auth/
│   ├── xiaomi-mipps-auth.service        # sed 已预应用：/usr/libexec/ → /usr/lib/xiaomi-mipps-auth/
│   └── 90-xiaomi-mipps-auth.rules       # 同上
├── xiaomi-sheng-keyboard-helper/
│   └── systemd/
│       ├── *.service                    # sed 已预应用
│       └── *.service                    # sed 已预应用
├── xiaomi-sheng-thp/
│   └── systemd/
│       └── xiaomi-sheng-thp.service     # sed 已预应用
├── xiaomi-sheng-fingerprint/
│   ├── systemd/
│   │   ├── sfsconfig.service            # sed 已预应用
│   │   ├── qteesupplicant.service       # 双 sed 已预应用
│   │   └── fprintd.service.d/
│   │       └── 10-xiaomi-sheng-fpc1553.conf
│   └── udev/
│       └── 99-qcomtee-fpc.rules
└── alsa-ucm-xiaomi-sheng/
    └── usr/
        └── share/alsa/ucm2/
            ├── Xiaomi/sheng/
            │   ├── HiFi.conf
            │   └── Xiaomi-Pad6SPro.conf
            └── conf.d/sm8550/
                └── Xiaomi-Pad6SPro.conf
```

## 3. 文件分类

| 类别 | 内容 | 处理方式 |
|------|------|----------|
| **无预处理文件** | sensor configs, udev rules, .conf drop-ins, ALSA UCM | 直接存放 |
| **sed 路径修正** | .service 文件中 /usr/libexec/ → /usr/lib/\<pkgname\>/ | 在 `files/` 下的文件中直接改为最终值 |

> libssc 的 `wait_for_qmi_service.patch` 已移除（上游已修复，不再需要）。

## 4. package-files.sh

**作用**：将 `files/<pkg>/` 打包为 `pkgs/<pkg>/files.tar.gz`，供 PKGBUILD 的 source 引用。

```bash
#!/bin/bash
# 遍历 files/ 下每个子目录，打包到对应 pkgs/<pkg>/
for dir in files/*/; do
    pkg=$(basename "$dir")
    if [ -d "$dir" ] && [ "$(ls -A "$dir")" ]; then
        tar czf "pkgs/$pkg/files.tar.gz" -C "$dir" .
    fi
done
```

**在 Makefile 中作为 fetch 阶段的新命令**：

```makefile
fetch:
	@bash scripts/package-files.sh
```

## 5. PKGBUILD 改动要点

| 包名 | 当前 PKGBUILD 中的预处理 | 修改后 |
|------|--------------------------|--------|
| fastrpc | source 包含 adsprpcd-sensorspd.service | source 改为 `files.tar.gz`，package() 从解压目录取文件 |
| libssc | prepare() 中 patch -Np1 | **删除 prepare()**，patch 不再需要 |
| xiaomi-sheng-sensors | source 包含 `sheng-sensors-files.tar.gz` | source 改为 `files.tar.gz`，路径对齐 |
| xiaomi-mipps-auth | prepare() 中 sed 替换路径 | 删除 prepare()，source 改为 `files.tar.gz` |
| xiaomi-sheng-keyboard-helper | prepare() 中 sed 替换路径 | 删除 prepare()，source 改为 `files.tar.gz` |
| xiaomi-sheng-thp | prepare() 中 sed 替换路径 | 删除 prepare()，source 改为 `files.tar.gz` |
| xiaomi-sheng-fingerprint | package() 中 sed 即时替换 | 改用预处理的 `files.tar.gz`，package() 安装即可 |
| alsa-ucm-xiaomi-sheng | 新增 | source `files.tar.gz`，package() 安装文件 |

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

记录每个 `files/<pkg>/` 中文件相对于上游原始文件所做的预处理操作。

## 8. 移出的文件

- `scripts/fetch-sources.sh` — 不再需要
- `pkgs/fastrpc/adsprpcd-sensorspd.service` — 移至 `files/fastrpc/`
- `pkgs/libssc/wait_for_qmi_service.patch` — **移除**（上游已修复）
- `pkgs/xiaomi-sheng-sensors/sheng-sensors-files.tar.gz` — 改为从 `files/xiaomi-sheng-sensors/` 打包
- `pkgs/xiaomi-sheng-sensors/sheng-sensors-files/` — 移至 `files/xiaomi-sheng-sensors/`
