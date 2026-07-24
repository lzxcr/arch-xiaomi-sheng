# arch-xiaomi-sheng 构建系统 — 便捷入口
# 用法: make <target>

SHELL := /bin/bash
.SHELLFLAGS = -euo pipefail -c

.PHONY: all fetch build repo rootfs clean

all: fetch build repo rootfs

# ① 从 debian-sheng 提取源文件
fetch:
	@echo "==> [1/4] 提取源文件 ..."
	@bash scripts/fetch-sources.sh

# ② 构建所有包
build:
	@echo "==> [2/4] 构建包 ..."
	@bash scripts/build-pkgs.sh

# ③ 创建本地仓库
repo:
	@echo "==> [3/4] 创建仓库 ..."
	@bash scripts/build-repo.sh

# ④ 组装 rootfs
rootfs:
	@echo "==> [4/4] 组装 rootfs 镜像 ..."
	@bash scripts/mkrootfs.sh

# 清理所有构建产物
clean:
	rm -rf out/pkgs out/repo out/rootfs out/sheng-repo.conf
	@echo "已清理构建产物"
