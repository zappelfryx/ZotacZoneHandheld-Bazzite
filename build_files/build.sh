#!/bin/bash
set -ouex pipefail

echo "=== Starte Zotac Zone Customizations ==="

REPO_RAW="https://raw.githubusercontent.com/OpenZotacZone/ZotacZone-Drivers/refs/heads/main"

# ==========================================
# 1. Kernel-Header & Build-Tools
# ==========================================
echo "-> Installiere Kernel-Header & Build-Tools..."
KERNEL_VERSION=$(ls /usr/lib/modules/ | grep -v 'debug' | sort -V | tail -n 1)
rpm-ostree install \
    kernel-devel-${KERNEL_VERSION} \
    gcc \
    make \
    python3-pip \
    wget \
    git

# python-evdev (für Dial-Daemon)
pip install evdev --break-system-packages

# ==========================================
# 2. OpenZONE Treiber (ZotacZone-Drivers)
# ==========================================
echo "-> Baue & installiere OpenZONE Kernel-Treiber..."

BUILD_DIR="/tmp/zotac_zone_build"
INSTALL_DIR="/usr/local/lib/zotac-zone"

mkdir -p "$BUILD_DIR"
mkdir -p "$INSTALL_DIR"

cd "$BUILD_DIR"

HID_FILES=(
    "zotac-zone-hid-core.c"
    "zotac-zone-hid-rgb.c"
    "zotac-zone-hid-input.c"
    "zotac-zone-hid-config.c"
    "zotac-zone.h"
)
PLATFORM_FILES=(
    "zotac-zone-platform.c"
    "firmware_attributes_class.h"
    "firmware_attributes_class.c"
)

for f in "${HID_FILES[@]}"; do
    wget -q "${REPO_RAW}/driver/hid/${f}"
done
for f in "${PLATFORM_FILES[@]}"; do
    wget -q "${REPO_RAW}/driver/platform/${f}"
done

cat > Makefile <<'EOF'
obj-m += zotac-zone-hid.o
zotac-zone-hid-y := zotac-zone-hid-core.o zotac-zone-hid-rgb.o zotac-zone-hid-input.o zotac-zone-hid-config.o
obj-m += firmware_attributes_class.o
obj-m += zotac-zone-platform.o
all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
EOF

make -C /usr/lib/modules/${KERNEL_VERSION}/build M=$(pwd) modules
cp *.ko "$INSTALL_DIR/"

cat > /usr/lib/systemd/system/zotac-zone-drivers.service <<EOF
[Unit]
Description=Load Zotac Zone Drivers (OpenZONE)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/modprobe led-class-multicolor
ExecStart=/usr/sbin/modprobe platform_profile
ExecStart=/usr/sbin/insmod ${INSTALL_DIR}/firmware_attributes_class.ko
ExecStart=/usr/sbin/insmod ${INSTALL_DIR}/zotac-zone-platform.ko
ExecStart=/usr/sbin/insmod ${INSTALL_DIR}/zotac-zone-hid.ko
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable zotac-zone-drivers.service

# ==========================================
# 3. Dial-Daemon installieren
# ==========================================
echo "-> Installiere Dial-Daemon..."

DIAL_SCRIPT="/usr/local/bin/zotac_dial_daemon.py"
wget -q -O "$DIAL_SCRIPT" "${REPO_RAW}/install_openzone_drivers.sh" || true
wget -q -O "$DIAL_SCRIPT" "${REPO_RAW}/driver/hid/zotac-zone.h" || true

cat > "$DIAL_SCRIPT" << 'PYEOF'
#!/usr/bin/env python3
# Zotac Zone Dial Daemon (OpenZONE - Raw HID)
import os, sys, glob, time, argparse
from evdev import UInput, ecodes as e

parser = argparse.ArgumentParser()
parser.add_argument("--left",  default="volume")
parser.add_argument("--right", default="brightness")
args = parser.parse_args()

VID = "1EE9"
PID = "1590"

ACTIONS = {
    "volume":            {"type": "key",       "up": e.KEY_VOLUMEUP,   "down": e.KEY_VOLUMEDOWN},
    "brightness":        {"type": "backlight", "step": 5},
    "scroll":            {"type": "rel",       "axis": e.REL_WHEEL, "up": 1,  "down": -1},
    "scroll_inverted":   {"type": "rel",       "axis": e.REL_WHEEL, "up": -1, "down": 1},
    "arrows_vertical":   {"type": "key",       "up": e.KEY_UP,         "down": e.KEY_DOWN},
    "arrows_horizontal": {"type": "key",       "up": e.KEY_RIGHT,      "down": e.KEY_LEFT},
    "media":             {"type": "key",       "up": e.KEY_NEXTSONG,   "down": e.KEY_PREVIOUSSONG},
    "page_scroll":       {"type": "key",       "up": e.KEY_PAGEUP,     "down": e.KEY_PAGEDOWN},
    "zoom":              {"type": "key",       "up": e.KEY_ZOOMIN,     "down": e.KEY_ZOOMOUT},
}

def find_backlight():
    paths = glob.glob("/sys/class/backlight/*")
    if not paths: return None
    paths.sort(key=lambda x: "amdgpu" not in x)
    return paths[0]

def set_backlight(path, direction, step_pct):
    try:
        max_v = int(open(os.path.join(path, "max_brightness")).read())
        cur_v = int(open(os.path.join(path, "brightness")).read())
        step  = max(1, int(max_v * (step_pct / 100.0)))
        new_v = max(0, min(cur_v + (step if direction=="up" else -step), max_v))
        open(os.path.join(path, "brightness"), "w").write(str(new_v))
    except Exception as ex:
        print(f"Backlight Err: {ex}")

def find_hidraw():
    for p in glob.glob("/sys/class/hidraw/hidraw*"):
        try:
            c = open(os.path.join(p, "device/uevent")).read().upper()
            if f"HID_ID={VID}:{PID}" in c or f"PRODUCT={VID}/{PID}" in c:
                return f"/dev/{os.path.basename(p)}"
        except: continue
    return None

def main():
    print(f"Dial Daemon. L:{args.left} R:{args.right}")
    backlight = find_backlight()
    cap = {e.EV_KEY: [], e.EV_REL: [e.REL_WHEEL]}
    for a in ACTIONS.values():
        if a["type"] == "key": cap[e.EV_KEY].extend([a["up"], a["down"]])
        elif a["type"] == "rel": cap[e.EV_REL].append(a["axis"])
    ui = UInput(cap, name="Zotac Zone Virtual Dials")

    while True:
        dev_path = find_hidraw()
        if not dev_path: time.sleep(3); continue
        try:
            with open(dev_path, "rb") as f:
                while True:
                    data = f.read(64)
                    if not data or len(data) < 4: break
                    if data[0] != 0x03 or data[3] == 0x00: continue
                    trig = data[3]
                    ac, di = None, None
                    if   trig == 0x10: ac, di = ACTIONS.get(args.left),  "down"
                    elif trig == 0x08: ac, di = ACTIONS.get(args.left),  "up"
                    elif trig == 0x02: ac, di = ACTIONS.get(args.right), "down"
                    elif trig == 0x01: ac, di = ACTIONS.get(args.right), "up"
                    if not ac: continue
                    if   ac["type"] == "backlight" and backlight: set_backlight(backlight, di, ac["step"])
                    elif ac["type"] == "key":
                        ui.write(e.EV_KEY, ac[di], 1); ui.write(e.EV_KEY, ac[di], 0); ui.syn()
                    elif ac["type"] == "rel":
                        ui.write(e.EV_REL, ac["axis"], ac[di]); ui.syn()
        except OSError: time.sleep(2)
        except Exception as err: print(f"Err: {err}"); time.sleep(2)

if __name__ == "__main__":
    main()
PYEOF
chmod +x "$DIAL_SCRIPT"

cat > /usr/lib/udev/rules.d/99-zotac-zone.rules <<'EOF'
KERNEL=="hidraw*", ATTRS{idVendor}=="1ee9", ATTRS{idProduct}=="1590", MODE="0666"
EOF

echo "uinput" > /usr/lib/modules-load.d/zotac-uinput.conf

cat > /usr/lib/systemd/system/zotac-dials.service <<EOF
[Unit]
Description=Zotac Zone Dial Daemon (OpenZONE)
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${DIAL_SCRIPT} --left volume --right brightness
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable zotac-dials.service

# ==========================================
# 4. CoolerControl (Fan-Steuerung)
# ==========================================
echo "-> Installiere CoolerControl via COPR..."
FEDORA_VER=$(rpm -E %fedora)
curl -fLo /etc/yum.repos.d/_copr_codifryed-CoolerControl.repo \
    "https://copr.fedorainfracloud.org/coprs/codifryed/CoolerControl/repo/fedora-${FEDORA_VER}/codifryed-CoolerControl-fedora-${FEDORA_VER}.repo"
rpm-ostree install coolercontrol

# ==========================================
# 5. Decky Plugins vorinstallieren
# ==========================================
echo "-> Lade Decky Plugins herunter..."
PLUGIN_DIR="/usr/share/decky-plugins-staging"
mkdir -p "$PLUGIN_DIR"
cd "$PLUGIN_DIR"

PLUGINS=(
    "rr1111/decky-zotaccontrol"
    "AAGaming00/unifydeck"
    "aarron-lee/SimpleDeckTDP"
    "xXJSONDeruloXx/Decky-Framegen"
    "xXJSONDeruloXx/decky-lsfg-vk"
    "moi952/decky-proton-launch"
    "koffcheck/potato-deals"
    "Threshold-Labs/deckydecks"
    "Wurielle/decky-launch-options"
    "jacobdonahoe/decky-game-optimizer"
    "Starkka15/junkstore"
    "moraroy/NonSteamLaunchersDecky"
    "sebet/decky-nonsteam-badges"
    "totallynotbakadestroyer/Decky-Achievement"
    "pns-sh/SteamHuntersDeckyPlugin"
    "cat-in-a-box/Decky-Translator"
    "lobinuxsoft/decky-capydeploy"
    "Lui92/decky-protondb-collections"
    "kEnder242/decky-trailers"
    "ebdevag/optideck-deckdeals"
    "samedayhurt/reshady"
    "Echarnus/DeckyMetacritic"
    "jwhitlow45/free-loader"
    "itsOwen/playcount-decky"
    "SteamGridDB/decky-steamgriddb"
    "DeckThemes/decky-theme-loader"
    "Tormak9970/TabMaster"
)

for repo in "${PLUGINS[@]}"; do
    DOWNLOAD_URL=$(curl -sf "https://api.github.com/repos/$repo/releases/latest" \
        | grep "browser_download_url.*\\.tar\\.gz" | cut -d '"' -f 4 | head -n 1)
    if [ -n "$DOWNLOAD_URL" ]; then
        wget -q --show-progress "$DOWNLOAD_URL" || echo "WARN: $repo konnte nicht geladen werden"
    else
        echo "WARN: Kein Release gefunden für $repo"
    fi
done

for f in *.tar.gz; do
    [ -f "$f" ] && tar -xzf "$f" && rm "$f"
done

mkdir -p /usr/etc/profile.d/
cat > /usr/etc/profile.d/decky-zotac-sync.sh << 'EOF'
#!/bin/bash
USER_PLUGIN_DIR="$HOME/homebrew/plugins"
if [ -d "/usr/share/decky-plugins-staging" ]; then
    mkdir -p "$USER_PLUGIN_DIR"
    cp -rn /usr/share/decky-plugins-staging/* "$USER_PLUGIN_DIR/"
fi
EOF
chmod +x /usr/etc/profile.d/decky-zotac-sync.sh

cd /
rm -rf "$BUILD_DIR"

echo "=== Zotac Zone Customizations beendet ==="
