# arch-xiaomi-sheng 构建系统 — 便捷入口
# 用法: make <target>（make help 查看全部目标）

SHELL := /bin/bash
.SHELLFLAGS = -euo pipefail -c

.DEFAULT_GOAL := help

.PHONY: all check files build repo rootfs clean help

all: build repo rootfs

# 快速、只读的仓库一致性检查
check:
	@bash scripts/check.sh

# 将 files/ 中本地维护的文件打成可复现归档
files:
	@bash scripts/package-files.sh $(FILES_ARGS)

# ① 在 clean chroot 中按阶段构建所有包
build:
	@bash scripts/build-pkgs.sh $(BUILD_ARGS)

# ② 将构建产物注册为本地 pacman 仓库
repo:
	@bash scripts/build-repo.sh

# ③ 用 pacstrap 组装可刷写的 rootfs 镜像
rootfs:
	@bash scripts/mkrootfs.sh $(ROOTFS_ARGS)

# 清理构建产物（--keep-cache 保留已下载的源码缓存）
clean:
	@bash scripts/clean.sh

help:
	@echo "arch-xiaomi-sheng 构建系统"
	@echo ""
	@echo "可用目标:"
	@echo "  all      完整流程：build → repo → rootfs"
	@echo "  check    检查脚本、包清单和 PKGBUILD 元数据"
	@echo "  files    生成本地 files.tar.gz 归档"
	@echo "  build    在 clean chroot 中按阶段构建全部 15 个包"
	@echo "  repo     将 out/pkgs/ 注册为本地 pacman 仓库"
	@echo "  rootfs   组装可刷写的 rootfs.img 与 boot.img"
	@echo "  clean    清理构建产物（--keep-cache 保留源码缓存）"
	@echo ""
	@echo "示例:"
	@echo "  make check"
	@echo "  make build BUILD_ARGS='--stage 0'"
	@echo "  make rootfs ROOTFS_ARGS='--desktop kde --size 8192'"
