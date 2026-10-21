#!/usr/bin/env bash
set -euo pipefail

IGPU_UUID="GPU-ebcc7355-bc7d-08ba-8873-730dd4b984a3"
EGPU_UUID="GPU-63241b58-1462-c809-2f4c-3919ed0779a9"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

echo "==> Authenticating sudo..."
sudo -v

echo "==> 0/8 Capturing current host bridge AER/Link status (05:00.0 & 06:00.0)..."
sudo lspci -vvv -s 05:00.0 -s 06:00.0 | grep -E '^[0-9a-f]|UESta:|CESta:|DevSta:|LnkSta:' || true

echo "==> 1/8 Updating systemd-boot kernel cmdline (pcie_aspm.policy=performance pcie_port_pm=off)..."
for entry in /boot/loader/entries/*.conf; do
  sudo test -f "$entry" || continue
  # Remove pci=realloc=off and pcie_aspm=off (pcie_aspm=off breaks ACPI _OSC on AMD root complexes)
  sudo sed -i 's/ pci=realloc=off//g; s/ pcie_aspm=off//g' "$entry"
  if ! sudo grep -q 'pcie_aspm.policy=performance' "$entry"; then
    sudo sed -i '/^options / s/$/ pcie_aspm.policy=performance/' "$entry"
  fi
  if ! sudo grep -q 'pcie_port_pm=off' "$entry"; then
    sudo sed -i '/^options / s/$/ pcie_port_pm=off/' "$entry"
  fi
  echo "    Updated $entry:"
  sudo grep '^options ' "$entry"
done

echo "==> 2/8 Pinning desktop session & VA-API to internal 5070 Ti (/etc/environment & kwin-drm.sh)..."
rm -f "$TARGET_HOME/.config/environment.d/10-kwin-egpu.conf"
sudo sed -i '/^KWIN_DRM_DEVICES=/d; /^KWIN_RENDER_NODES=/d; /^CUDA_DEVICE_ORDER=/d; /^CUDA_VISIBLE_DEVICES=/d; /^NVD_GPU=/d' /etc/environment 2>/dev/null || true
cat <<EOF | sudo tee -a /etc/environment >/dev/null
CUDA_DEVICE_ORDER=PCI_BUS_ID
CUDA_VISIBLE_DEVICES=${IGPU_UUID}
NVD_GPU=0
EOF

mkdir -p "$TARGET_HOME/.config/plasma-workspace/env"
cat > "$TARGET_HOME/.config/plasma-workspace/env/kwin-drm.sh" <<EOF
#!/bin/sh
# Use colon-free udev symlinks (/dev/dri/igpu-card, /dev/dri/igpu-render, and /dev/dri/by-path/platform-evdi.*-card)
# because KWin splits KWIN_DRM_DEVICES and KWIN_RENDER_NODES on ':' characters.
if [ -e /dev/dri/igpu-card ]; then
    export KWIN_DRM_DEVICES="/dev/dri/igpu-card:/dev/dri/by-path/platform-evdi.0-card:/dev/dri/by-path/platform-evdi.1-card:/dev/dri/by-path/platform-evdi.2-card:/dev/dri/by-path/platform-evdi.3-card"
fi
if [ -e /dev/dri/igpu-render ]; then
    export KWIN_RENDER_NODES="/dev/dri/igpu-render"
fi
export CUDA_DEVICE_ORDER="PCI_BUS_ID"
export CUDA_VISIBLE_DEVICES="${IGPU_UUID}"
export NVD_GPU="0"
EOF
chmod +x "$TARGET_HOME/.config/plasma-workspace/env/kwin-drm.sh"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/plasma-workspace/env/kwin-drm.sh"

echo "==> 2b/8 Configuring DisplayLink EVDI virtual DRM nodes at boot (/etc/modules-load.d/evdi.conf & /etc/modprobe.d/evdi.conf)..."
printf 'options evdi initial_device_count=4\n' | sudo tee /etc/modprobe.d/evdi.conf >/dev/null
printf 'evdi\n' | sudo tee /etc/modules-load.d/evdi.conf >/dev/null

echo "==> 3/8 Installing /usr/local/bin/nvidia-egpu-gen3-cap (Caps Barlow Ridge 08:00.0 & 5080 09:00.0 at Gen3 + HASD before nvidia loads)..."
sudo tee /usr/local/bin/nvidia-egpu-gen3-cap >/dev/null <<'EOF'
#!/bin/sh
# Cap the PCIe bridge directly above the RTX 5080 eGPU (Intel JHL9480 08:00.0) and the GPU
# itself (10de:2c02) at Gen3 (8 GT/s) with Hardware Autonomous Speed Disable (HASD, 0x20),
# and retrain the link BEFORE nvidia.ko binds and boots the GSP.
# Based on NVIDIA/open-gpu-kernel-modules#979 & djanice1980/eGPU-Blackwell-Stability.

klog() {
    if [ -w /dev/kmsg ]; then
        printf '<6>[nvidia-egpu-cap] %s\n' "$*" > /dev/kmsg 2>/dev/null || true
    fi
}

TARGET_GEN=3
for gpu_dir in /sys/bus/pci/devices/*; do
    [ -d "$gpu_dir" ] || continue
    vendor=$(cat "$gpu_dir/vendor" 2>/dev/null || true)
    device=$(cat "$gpu_dir/device" 2>/dev/null || true)
    if [ "$vendor" = "0x10de" ] && [ "$device" = "0x2c02" ]; then
        GPU=$(basename "$gpu_dir")
        BRIDGE=$(basename "$(dirname "$(readlink -f "$gpu_dir")")")
        if [ -e "$gpu_dir/driver" ]; then
            klog "Driver already bound to $GPU; skipping link retrain"
            exit 0
        fi
        old_hex=$(/usr/bin/setpci -s "$BRIDGE" CAP_EXP+30.w 2>/dev/null || true)
        if [ -z "$old_hex" ] || [ "$old_hex" = "ffff" ]; then
            klog "Bridge $BRIDGE not responding ($old_hex); skipping"
            exit 0
        fi
        old=$((0x$old_hex))
        new=$(( (old & ~0xf) | TARGET_GEN | 0x20 ))
        new_hex=$(printf '%04x' "$new")
        /usr/bin/setpci -s "$BRIDGE" "CAP_EXP+30.w=$new_hex" 2>/dev/null || true

        gold_hex=$(/usr/bin/setpci -s "$GPU" CAP_EXP+30.w 2>/dev/null || true)
        if [ -n "$gold_hex" ] && [ "$gold_hex" != "ffff" ]; then
            gold=$((0x$gold_hex))
            gnew=$(( (gold & ~0xf) | TARGET_GEN | 0x20 ))
            gnew_hex=$(printf '%04x' "$gnew")
            /usr/bin/setpci -s "$GPU" "CAP_EXP+30.w=$gnew_hex" 2>/dev/null || true
        fi

        # Trigger link retrain on the upstream bridge (bit 5 = 0x0020 in LnkCtl CAP_EXP+10.w)
        /usr/bin/setpci -s "$BRIDGE" "CAP_EXP+10.w=0020:0020" 2>/dev/null || true
        i=0
        while [ "$i" -lt 20 ]; do
            v_hex=$(/usr/bin/setpci -s "$BRIDGE" CAP_EXP+12.w 2>/dev/null || echo 0)
            v=$((0x$v_hex))
            training=$(( (v >> 11) & 1 ))
            dl_active=$(( (v >> 13) & 1 ))
            speed=$(( v & 0xf ))
            if [ "$training" -eq 0 ] && [ "$dl_active" -eq 1 ] && [ "$speed" -le "$TARGET_GEN" ]; then
                break
            fi
            sleep 0.05 2>/dev/null || true
            i=$((i + 1))
        done
        final_hex=$(/usr/bin/setpci -s "$BRIDGE" CAP_EXP+12.w 2>/dev/null || echo 0)
        final=$((0x$final_hex))
        klog "Capped $BRIDGE <-> $GPU to Gen$((final & 0xf)) x$(((final >> 4) & 0x3f)) + HASD (LnkCtl2: $old_hex -> $new_hex)"
    fi
done
exit 0
EOF
sudo chmod 0755 /usr/local/bin/nvidia-egpu-gen3-cap

echo "==> 4/8 Configuring /etc/modprobe.d/zz-nvidia-egpu.conf (sorts last, runs Gen3 cap before nvidia loads)..."
sudo rm -f /etc/modprobe.d/thunderbolt.conf /etc/modprobe.d/thunderbolt-egpu.conf /etc/modprobe.d/nvidia-egpu-power.conf
sudo tee /etc/modprobe.d/zz-nvidia-egpu.conf >/dev/null <<'EOF'
options thunderbolt host_reset=0 clx=0
options nvidia NVreg_DynamicPowerManagement=0x00
options snd_hda_intel power_save=0
install nvidia /usr/local/bin/nvidia-egpu-gen3-cap; /usr/bin/modprobe --ignore-install nvidia $CMDLINE_OPTS
EOF

echo "==> 5/8 Writing /etc/udev/rules.d/72-egpu-power.rules..."
sudo rm -f /etc/udev/rules.d/99-egpu-power.rules /etc/udev/rules.d/99-egpu-nvidia5080.rules
sudo tee /etc/udev/rules.d/72-egpu-power.rules >/dev/null <<'EOF'
# 1. Keep USB4 / Thunderbolt devices awake (only where power/control sysfs attribute exists)
ACTION=="add|change", SUBSYSTEM=="thunderbolt", TEST=="power/control", ATTR{power/control}="on"

# 2. Keep AMD USB4 Root Port (0000:00:02.1), ASMedia ASM4242 USB4 (0x1b21),
#    Intel JHL9480 TB5 eGPU bridges (0x8086:0x5786), and NVIDIA GPUs (0x10de) in D0
ACTION=="add|change", SUBSYSTEM=="pci", KERNEL=="0000:00:02.1", ATTR{power/control}="on", TEST=="d3cold_allowed", ATTR{d3cold_allowed}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x1b21", ATTR{power/control}="on", TEST=="d3cold_allowed", ATTR{d3cold_allowed}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x5786", ATTR{power/control}="on", TEST=="d3cold_allowed", ATTR{d3cold_allowed}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{power/control}="on", TEST=="d3cold_allowed", ATTR{d3cold_allowed}="0"

# 3. Disable PCIe hardware ASPM & PCI-PM L1 substates across the USB4 <-> eGPU chain
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x1b21", TEST=="link/l1_2_aspm", ATTR{link/l1_2_aspm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x1b21", TEST=="link/l1_1_aspm", ATTR{link/l1_1_aspm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x1b21", TEST=="link/l1_2_pcipm", ATTR{link/l1_2_pcipm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x1b21", TEST=="link/l1_1_pcipm", ATTR{link/l1_1_pcipm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x1b21", TEST=="link/l1_aspm", ATTR{link/l1_aspm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x1b21", TEST=="link/l0s_aspm", ATTR{link/l0s_aspm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x1b21", TEST=="link/clkpm", ATTR{link/clkpm}="0"

ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x5786", TEST=="link/l1_2_aspm", ATTR{link/l1_2_aspm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x5786", TEST=="link/l1_1_aspm", ATTR{link/l1_1_aspm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x5786", TEST=="link/l1_2_pcipm", ATTR{link/l1_2_pcipm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x5786", TEST=="link/l1_1_pcipm", ATTR{link/l1_1_pcipm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x5786", TEST=="link/l1_aspm", ATTR{link/l1_aspm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x5786", TEST=="link/l0s_aspm", ATTR{link/l0s_aspm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x5786", TEST=="link/clkpm", ATTR{link/clkpm}="0"

ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x2c02|0x22e9", TEST=="link/l1_2_aspm", ATTR{link/l1_2_aspm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x2c02|0x22e9", TEST=="link/l1_1_aspm", ATTR{link/l1_1_aspm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x2c02|0x22e9", TEST=="link/l1_2_pcipm", ATTR{link/l1_2_pcipm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x2c02|0x22e9", TEST=="link/l1_1_pcipm", ATTR{link/l1_1_pcipm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x2c02|0x22e9", TEST=="link/l1_aspm", ATTR{link/l1_aspm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x2c02|0x22e9", TEST=="link/l0s_aspm", ATTR{link/l0s_aspm}="0"
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x2c02|0x22e9", TEST=="link/clkpm", ATTR{link/clkpm}="0"

# 4. Prevent snd_hda_intel from binding to headless RTX 5080 Audio (10de:22e9)
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x22e9", ATTR{driver_override}="none"

# 5. Create colon-free symlinks for internal RTX 5070 Ti (10de:2f58) for KWin
ACTION=="add|change", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ATTRS{vendor}=="0x10de", ATTRS{device}=="0x2f58", SYMLINK+="dri/igpu-card"
ACTION=="add|change", SUBSYSTEM=="drm", KERNEL=="renderD[0-9]*", ATTRS{vendor}=="0x10de", ATTRS{device}=="0x2f58", SYMLINK+="dri/igpu-render"

# 6. Isolate headless RTX 5080 (10de:2c02) DRM nodes (card* and renderD*) from desktop/Wayland/Chrome/VA-API
#    CUDA (/dev/nvidia*) remains 0666 for explicit compute workloads via CUDA_VISIBLE_DEVICES.
ACTION=="add|change", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ATTRS{vendor}=="0x10de", ATTRS{device}=="0x2c02", ENV{ID_SEAT}="seat_headless", TAG-="seat", TAG-="master-of-seat", TAG-="uaccess", MODE="0000", RUN+="/usr/bin/setfacl -b /dev/dri/%k"
ACTION=="add|change", SUBSYSTEM=="drm", KERNEL=="renderD[0-9]*", ATTRS{vendor}=="0x10de", ATTRS{device}=="0x2c02", ENV{ID_SEAT}="seat_headless", TAG-="seat", TAG-="uaccess", MODE="0000", RUN+="/usr/bin/setfacl -b /dev/dri/%k"
EOF

echo "==> 6/8 Installing nvidia-powerd eGPU filter shim (for 5070 Ti 140W Dynamic Boost)..."
sudo mkdir -p /usr/local/lib /etc/systemd/system/nvidia-powerd.service.d
sudo gcc -shared -fPIC -O2 -o /usr/local/lib/nvidia-powerd-egpu-fix.so "$SCRIPT_DIR/nvidia-powerd-egpu-fix.c" -ldl
sudo chmod 0755 /usr/local/lib/nvidia-powerd-egpu-fix.so
sudo tee /etc/systemd/system/nvidia-powerd.service.d/egpu-fix.conf >/dev/null <<'EOF'
[Service]
Environment="LD_PRELOAD=/usr/local/lib/nvidia-powerd-egpu-fix.so"
EOF

echo "==> 7/8 Configuring boot-time true P0 lock (-lgc & -lmc) & power limit service for RTX 5080..."
sudo tee /etc/systemd/system/nvidia-egpu-powerlimit.service >/dev/null <<'EOF'
[Unit]
Description=Lock Headless RTX 5080 eGPU in True P0 (Core+Mem Clocks) & Unlock 5070 Ti TGP
After=nvidia-persistenced.service nvidia-powerd.service
Wants=nvidia-persistenced.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c ' \
  [ -w /sys/class/firmware-attributes/asus-armoury/attributes/nv_tgp/current_value ] && echo 115 > /sys/class/firmware-attributes/asus-armoury/attributes/nv_tgp/current_value || true; \
  [ -w /sys/class/firmware-attributes/asus-armoury/attributes/nv_dynamic_boost/current_value ] && echo 25 > /sys/class/firmware-attributes/asus-armoury/attributes/nv_dynamic_boost/current_value || true; \
  if /usr/bin/nvidia-smi -L | grep -q GPU-ebcc7355-bc7d-08ba-8873-730dd4b984a3; then \
    /usr/bin/nvidia-smi -i GPU-ebcc7355-bc7d-08ba-8873-730dd4b984a3 -pm 1 || true; \
  fi; \
  if /usr/bin/nvidia-smi -L | grep -q GPU-63241b58-1462-c809-2f4c-3919ed0779a9; then \
    /usr/bin/nvidia-smi -i GPU-63241b58-1462-c809-2f4c-3919ed0779a9 -pm 1 && \
    /usr/bin/nvidia-smi -i GPU-63241b58-1462-c809-2f4c-3919ed0779a9 -pl 400 && \
    /usr/bin/nvidia-smi -i GPU-63241b58-1462-c809-2f4c-3919ed0779a9 -lmc 10000,15001 && \
    /usr/bin/nvidia-smi -i GPU-63241b58-1462-c809-2f4c-3919ed0779a9 -lgc 2100,3090 || true; \
  fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable nvidia-powerd.service nvidia-persistenced.service nvidia-egpu-powerlimit.service

echo "==> 8/8 Embedding setpci, gen3-cap, udev & modprobe rules in initramfs and rebuilding (mkinitcpio -P)..."
sudo sed -i 's|^[[:space:]]*BINARIES=.*|BINARIES=(/usr/bin/setpci /usr/local/bin/nvidia-egpu-gen3-cap)|' /etc/mkinitcpio.conf
sudo sed -i 's|^[[:space:]]*FILES=.*|FILES=(/etc/modprobe.d/zz-nvidia-egpu.conf /etc/udev/rules.d/72-egpu-power.rules)|' /etc/mkinitcpio.conf
sudo mkinitcpio -P

echo "==> Configuration staged! Please reboot now."
