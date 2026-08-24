#!/usr/bin/env bash
# Build an atomic local pacman repository from out/pkgs.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

STAGING_DIR=""

cleanup() {
  [[ -z "$STAGING_DIR" ]] || rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

main() {
  local repository_config="$OUT_DIR/sheng-repo.conf"
  local -a packages=()

  (($# == 0)) || die "build-repo.sh 不接受参数"
  require_commands repo-add
  [[ -d "$OUT_PKGS_DIR" ]] || die "包目录不存在: $OUT_PKGS_DIR"

  mapfile -t packages < <(
    find "$OUT_PKGS_DIR" -maxdepth 1 -type f -name '*.pkg.tar.*' -print | sort
  )
  ((${#packages[@]} > 0)) || die "没有找到构建包；请先运行 make build"

  mkdir -p "$OUT_DIR"
  STAGING_DIR="$(mktemp -d "$OUT_DIR/.repo.XXXXXX")"

  msg "复制 ${#packages[@]} 个包到暂存仓库"
  cp -- "${packages[@]}" "$STAGING_DIR/"

  repo-add "$STAGING_DIR/sheng.db.tar.gz" "$STAGING_DIR"/*.pkg.tar.*

  rm -rf "$OUT_REPO_DIR"
  mv "$STAGING_DIR" "$OUT_REPO_DIR"
  STAGING_DIR=""

  cat > "$repository_config" <<EOF
# 由 scripts/build-repo.sh 生成
[sheng]
SigLevel = Never
Server = file://$OUT_REPO_DIR
EOF

  msg "仓库已生成: $OUT_REPO_DIR"
  msg "宿主 pacman 配置片段: $repository_config"
}

main "$@"
