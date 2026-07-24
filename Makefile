# arch-xiaomi-sheng 构建系统 — 便捷入口
# 用法: make <target>

SHELL := /bin/bash
.SHELLFLAGS = -euo pipefail -c

.PHONY: all build repo rootfs clean

all: build repo rootfs

# ① 构建所有包
build:
	@echo "==> [1/3] 构建包 ..."
	@bash scripts/build-pkgs.sh

# ② 创建本地仓库
repo:
	@echo "==> [2/3] 创建仓库 ..."
	@bash scripts/build-repo.sh

# ③ 组装 rootfs
rootfs:
	@echo "==> [3/3] 组装 rootfs 镜像 ..."
	@bash scripts/mkrootfs.sh

# 清理所有构建产物
clean:
	@bash scripts/clean.sh
