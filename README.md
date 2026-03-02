# AMD Radeon AI Pro R9700 — Ubuntu Fan Fix (Hybrid GPU Mode)

Fix for the AMD Radeon AI Pro R9700 fan running at full speed (~2677 RPM) at idle when used in hybrid GPU mode on Linux.

## The Problem

In a hybrid GPU setup where the R9700 has **no display connected** (secondary GPU handles display output), the kernel's runtime power management suspends the R9700 into **D3hot** to save power. In D3hot, the amdgpu driver loses control of the fan and the card's hardware controller defaults to a fixed ~2677 RPM — loud at idle, regardless of temperature.

## Root Cause

- **D3cold not available**: The board's ACPI firmware doesn't provide a `_PR3` power resource for the PCIe slot, so the GPU cannot reach D3cold (full power removal). It stalls at D3hot.
- **No manual fan control**: RDNA 4 amdgpu driver does not expose writable `pwm1` or a working `fan1_enable` via sysfs. Manual fan speed control is not possible from userspace.
- **Hardware fan default**: In D3hot, the card's SMU defaults to ~2677 RPM with no driver override possible.

## The Fix

Keep the GPU in **D0** (fully active) via a udev rule. In D0:

- amdgpu retains fan control
- Auto fan curve runs at ~20% PWM at idle temperatures (28–30°C)
- Near-silent at idle
- GFXOFF is still active — the GFX core power-gates inside D0, so idle power draw remains low

## Tested On

- **GPU:** AMD Radeon AI Pro R9700 (PCI ID `1002:7551`, RDNA 4 / Navi 48)
- **OS:** Ubuntu 24.04.4 LTS
- **Kernel:** 6.17.0 (amdgpu in-kernel driver)
- **Setup:** Hybrid mode — R9700 for compute/AI (no display), secondary AMD GPU for display

## Installation

```bash
git clone https://github.com/bigmalloy/ai-pro-r9700-ubuntu-fan-fix.git
cd ai-pro-r9700-ubuntu-fan-fix
chmod +x r9700-power.sh
sudo ./r9700-power.sh apply
```

## Usage

```bash
# Apply fix (install udev rule + set D0 immediately)
sudo ./r9700-power.sh apply

# Remove fix and restore runtime PM
sudo ./r9700-power.sh remove
```

### What `apply` does

1. Installs `/etc/udev/rules.d/99-r9700-power.rules` — sets `power/control=on` for PCI ID `1002:7551` at boot
2. Immediately applies `power/control=on` to the live device
3. Removes the old `99-r9700-sleep.rules` if present

The fix persists across reboots via the udev rule.

## Why Not Keep It in D3hot?

| State | Fan | Power draw | Driver fan control |
|-------|-----|------------|--------------------|
| D3hot | ~2677 RPM (hardware default) | Very low | None |
| D0    | ~20% PWM auto (~quiet) | Low (GFXOFF active) | Yes |
| D3cold | Off | Zero | N/A — not supported on this board |

D3cold would be ideal (fan off, zero power) but requires ACPI `_PR3` power resources in the board firmware, which most consumer boards don't provide for PCIe slots.

## Fan Control Limitations (RDNA 4)

As of kernel 6.17, the amdgpu driver for RDNA 4 does not support manual fan control:

- `fan1_enable` — returns `EINVAL` on read/write
- `pwm1` — read-only (`r--r--r--`)
- `pwm1_enable` — not present
- `gpu_od` — not present

The auto fan curve in D0 is the only option available from userspace currently. This may improve in future driver releases.
