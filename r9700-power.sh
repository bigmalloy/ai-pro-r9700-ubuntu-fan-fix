#!/usr/bin/env bash
# r9700-power.sh — Keep R9700 in D0 to prevent hardware fan defaulting to ~2677 RPM
#
# Root cause: in D3hot the amdgpu driver loses fan control and the card's
# hardware controller defaults to a fixed high RPM. D3cold is not supported
# on this board (no ACPI _PR3 power resource). Keeping the GPU in D0 lets
# amdgpu auto-control the fan quietly (~20% PWM at idle).
#
# Usage:
#   sudo ./r9700-power.sh apply   — install udev rule + apply now
#   sudo ./r9700-power.sh remove  — uninstall and restore runtime PM

set -euo pipefail

GPU_PCI="0000:03:00.0"
UDEV_RULE="/etc/udev/rules.d/99-r9700-power.rules"
OLD_SLEEP_RULE="/etc/udev/rules.d/99-r9700-sleep.rules"
GPU_PWR="/sys/bus/pci/devices/${GPU_PCI}/power"

RED='\033[0;31m'; GRN='\033[0;32m'; CYN='\033[0;36m'; RST='\033[0m'

die()  { echo -e "${RED}ERROR: $*${RST}" >&2; exit 1; }
info() { echo -e "${CYN}▶ $*${RST}"; }
ok()   { echo -e "${GRN}✔ $*${RST}"; }

[[ $EUID -eq 0 ]] || die "Run with sudo: sudo $0 $*"

CMD="${1:-}"
[[ -n "$CMD" ]] || die "Usage: sudo $0 {apply|remove}"

case "$CMD" in
apply)
    info "Installing udev rule..."
    cat > "$UDEV_RULE" << 'EOF'
# Keep R9700 in D0 — prevents hardware fan defaulting to 2677 RPM in D3hot
ACTION=="add", SUBSYSTEM=="pci", ENV{PCI_ID}=="1002:7551", ATTR{power/control}="on"
EOF
    ok "Rule installed: $UDEV_RULE"

    if [[ -f "$OLD_SLEEP_RULE" ]]; then
        rm "$OLD_SLEEP_RULE"
        ok "Removed old gpu-sleep rule: $OLD_SLEEP_RULE"
    fi

    udevadm control --reload-rules
    echo on > "$GPU_PWR/control"
    ok "GPU locked to D0 (power/control=on)"

    echo ""
    echo "  PCI state : $(cat /sys/bus/pci/devices/${GPU_PCI}/power_state 2>/dev/null || echo '?')"
    echo "  PM control: $(cat ${GPU_PWR}/control 2>/dev/null || echo '?')"
    echo "  Fan PWM   : $(cat /sys/class/hwmon/hwmon4/pwm1 2>/dev/null || echo '?') / 255"
    ;;

remove)
    [[ -f "$UDEV_RULE" ]] && rm "$UDEV_RULE" && ok "Removed $UDEV_RULE" || true
    udevadm control --reload-rules
    echo auto > "$GPU_PWR/control"
    ok "Restored runtime PM to auto"
    ;;

*)
    die "Usage: sudo $0 {apply|remove}"
    ;;
esac
