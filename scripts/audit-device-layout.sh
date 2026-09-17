#!/usr/bin/env bash
# Read-only UFS/GPT and boot hand-off audit for Xiaomi sheng.

set -euo pipefail

readonly PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SLOT_TOOL="$PROJECT_DIR/files/install/mkinitcpio-bootflash/sheng-boot-slot"

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

section() {
    printf '\n[%s]\n' "$1"
}

size_by_label() {
    local label="$1"
    local link="/dev/disk/by-partlabel/$label"

    [[ -L "$link" ]] || return 1
    lsblk -bdnro SIZE "$(readlink -f -- "$link")"
}

human_size() {
    numfmt --to=iec-i --suffix=B "$1"
}

main() {
    local sysdev dev label count size table_line
    local -a ufs_devices=()
    local -a critical_labels=(
        xbl_a xbl_b abl_a abl_b boot_a boot_b vbmeta_a vbmeta_b
        dtbo_a dtbo_b vendor_boot_a vendor_boot_b uefivarstore
    )

    for sysdev in /sys/block/sd?; do
        [[ -e "$sysdev" ]] || continue
        [[ "$(readlink -f -- "$sysdev/device")" == *ufshc* ]] || continue
        ufs_devices+=("/dev/${sysdev##*/}")
    done
    ((${#ufs_devices[@]} > 0)) || {
        warn "no UFS LUNs were discovered"
        return 1
    }

    section "boot hand-off"
    bash "$SLOT_TOOL" status
    if [[ -d /sys/firmware/acpi ]]; then
        printf 'ACPI:        present\n'
    else
        printf 'ACPI:        absent\n'
    fi
    findmnt -no SOURCE,FSTYPE,TARGET / 2>/dev/null || true
    findmnt -no SOURCE,FSTYPE,TARGET /boot 2>/dev/null || true

    section "UFS logical units"
    lsblk -bdno NAME,SIZE,LOG-SEC,PHY-SEC,MODEL "${ufs_devices[@]}"

    section "critical partition labels"
    for label in "${critical_labels[@]}"; do
        count=0
        if [[ -d /dev/disk/by-partlabel ]]; then
            while IFS= read -r table_line; do
                [[ "$table_line" == "$label" ]] && ((count += 1))
            done < <(lsblk -nrpo PARTLABEL "${ufs_devices[@]}" 2>/dev/null || true)
        fi
        if ((count == 1)); then
            printf 'ok       %s\n' "$label"
        elif ((count == 0)); then
            warn "missing critical label: $label"
        else
            warn "duplicate critical label ($count copies): $label"
        fi
    done

    section "capacity-sensitive partitions"
    if size="$(size_by_label esp 2>/dev/null)"; then
        printf 'esp:       %s\n' "$(human_size "$size")"
    else
        warn "ESP partition label is missing"
    fi
    if size="$(size_by_label super 2>/dev/null)"; then
        printf 'super:     %s\n' "$(human_size "$size")"
        if ((size < 1024 * 1024 * 1024)); then
            warn "super is below 1 GiB; full Android dynamic partitions/OTA cannot fit"
        fi
    else
        warn "super partition label is missing"
    fi

    section "GPT validation"
    if ((EUID != 0)); then
        warn "run with sudo to execute read-only sfdisk --verify on every UFS LUN"
    else
        for dev in "${ufs_devices[@]}"; do
            printf '%s: ' "$dev"
            if sfdisk --verify "$dev" >/dev/null; then
                printf 'valid\n'
            else
                printf 'INVALID\n'
            fi

            while IFS='|' read -r table_line label; do
                [[ -z "$table_line" ]] && continue
                if [[ "$table_line" == *'00000000-0000-0000-0000-000000000000'* && \
                      "$label" == last_parti ]]; then
                    printf '%s: unused Qualcomm last_parti sentinel (ignored by GPT readers)\n' "$dev"
                else
                    warn "$dev contains an unexpected zero-length GPT entry: $table_line $label"
                fi
            done < <(
                sfdisk -o Device,Start,Size,Type-UUID,Name --list "$dev" 2>/dev/null |
                    awk '$1 ~ /^\/dev\// && $3 == "0B" {name=$5; $5=""; print $0 "|" name}'
            )
        done
    fi

    section "assessment boundary"
    printf '%s\n' \
        'This command is read-only. A valid GPT is not permission to repartition.' \
        'Preserve all boot-firmware LUNs and make raw GPT plus partition backups' \
        'before any separately approved offline migration.'
}

main "$@"
