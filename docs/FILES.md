# 本地设备文件

`files/` 保存无法直接由上游源码安装，或必须为 Arch/sheng 调整的版本化输入。
生成的 `pkgs/*/files.tar.gz` 是派生物，由 `.gitignore` 排除。

## 目录语义

```text
files/
├── direct/<pkg>/   按根目录布局保存的大型数据树、固件和配置
└── install/<pkg>/  PKGBUILD 明确安装的 systemd、udev、drop-in 或脚本
```

`package-files.sh` 先复制 `direct`，再复制 `install`；相同相对路径由 `install`
版本覆盖。归档排除历史 `preprocess.sh` 文件，并固定条目顺序、mtime、uid/gid。

```bash
make files
./scripts/package-files.sh --pkg xiaomi-sheng-sensors
```

## 文件来源与本地改动

| 包 | 来源 | 本地处理 |
|---|---|---|
| `alsa-ucm-xiaomi-sheng` | `ianchb/debian-sheng` 的 ALSA UCM2 | `conf.d` 使用相对符号链接，避免重复配置 |
| `xiaomi-sheng-sensors` | `ianchb/debian-sheng` 的 qcom 数据树 | 保留 DSP、sensor registry、persist 与 socinfo 布局；补充 udev 与 persist tmpfiles 规则 |
| `mkinitcpio-bootflash` | 本仓库维护 | 适配 mkinitcpio post hook；支持 `BOOTFLASH_NO_FLASH=1` |
| `xiaomi-mipps-auth` | 上游 0.21 Debian 文件 | `/usr/libexec` 改为 `/usr/lib/xiaomi-mipps-auth` |
| `xiaomi-charger-mode` | 上游服务 | 使用 Arch 私有程序路径 |
| `xiaomi-sheng-devauth` | debian-sheng 服务/drop-in | 合并 qteesupplicant 依赖 |
| `xiaomi-sheng-fingerprint` | 上游 0.1.4 | 私有 libfprint、QTEE listener 与 Arch systemd 路径 |
| `xiaomi-sheng-keyboard-helper` | 上游 0.2.0 | 私有程序路径；sensors PD 服务名迁移到 HexagonRPC 0.6.0 |
| `xiaomi-sheng-thp` | 上游 0.3.9 | 私有程序路径；保留 `RuntimeDirectory` |

HexagonRPC 自 0.6.0 起自行安装 systemd、udev、sysusers 和默认配置，因此本仓库不再
维护 `files/install/hexagonrpc` 覆盖。

## 维护约束

- 不在 `files/direct` 中批量格式化或修改专有二进制；只做可追溯的替换。
- systemd/udev 文件修改后，同时检查 PKGBUILD 安装目标和相关单元引用。
- 新增 `files/<kind>/<pkg>` 时必须存在同名 PKGBUILD，且 PKGBUILD 引用
  `files.tar.gz`；`make check` 会验证这一点。
- 大型设备文件更新应记录来源仓库、日期或上游版本，并在提交前比较文件清单。
- 重复运行 `make files` 应得到相同哈希；若输入未变而哈希变化，应先修复归档过程。
