# arch-xiaomi-sheng 构建系统 — 便捷入口
# 用法: make <target>（make help 查看全部目标）

SHELL := /bin/bash
.SHELLFLAGS = -euo pipefail -c

.PHONY: all build repo rootfs clean help

all: build repo rootfs

# ① 在 clean chroot 中按拓扑序构建所有包
build:
	@bash scripts/build-pkgs.sh

# ② 将构建产物注册为本地 pacman 仓库
repo:
	@bash scripts/build-repo.sh

# ③ 用 pacstrap 组装可刷写的 rootfs 镜像
rootfs:
	@bash scripts/mkrootfs.sh

# 清理构建产物（--keep-cache 保留已下载的源码缓存）
clean:
	@bash scripts/clean.sh

help:
	@echo "arch-xiaomi-sheng 构建系统"
	@echo ""
	@echo "可用目标:"
	@echo "  all      完整流程: build → repo → rootfs"
	@echo "  build    在 clean chroot 中按拓扑序构建全部 15 个包"
	@echo "  repo     将 out/pkgs/ 注册为本地 pacman 仓库"
	@echo "  rootfs   用 pacstrap 组装可刷写的 rootfs.img"
	@echo "  clean    清理构建产物（--keep-cache 保留源码缓存）"
	@echo ""
	@echo "示例:"
	@echo "  make build && make repo && make rootfs"
	@echo "  bash scripts/build-pkgs.sh --tier 0   # 只构建 tier 0"
