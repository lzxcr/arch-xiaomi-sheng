#!/usr/bin/env bash
# Shared paths, configuration and output helpers for repository scripts.

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SCRIPTS_DIR
PROJECT_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
readonly PROJECT_DIR

# shellcheck source=scripts/config.sh
source "$SCRIPTS_DIR/config.sh"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  readonly _COLOR_BLUE=$'\033[1;34m'
  readonly _COLOR_YELLOW=$'\033[1;33m'
  readonly _COLOR_RED=$'\033[1;31m'
  readonly _COLOR_RESET=$'\033[0m'
else
  readonly _COLOR_BLUE=""
  readonly _COLOR_YELLOW=""
  readonly _COLOR_RED=""
  readonly _COLOR_RESET=""
fi

msg() {
  printf '%s==>%s %s\n' "$_COLOR_BLUE" "$_COLOR_RESET" "$*"
}

warn() {
  printf '%s!>%s %s\n' "$_COLOR_YELLOW" "$_COLOR_RESET" "$*" >&2
}

die() {
  printf '%s!!>%s %s\n' "$_COLOR_RED" "$_COLOR_RESET" "$*" >&2
  exit 1
}

require_commands() {
  local command_name
  local -a missing=()

  for command_name in "$@"; do
    command -v "$command_name" &>/dev/null || missing+=("$command_name")
  done

  ((${#missing[@]} == 0)) || die "缺少命令: ${missing[*]}"
}

require_option_value() {
  local option="$1"
  local value="${2:-}"
  [[ -n "$value" && "$value" != --* ]] || die "$option 需要一个参数"
}
