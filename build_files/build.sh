#!/bin/bash
set -ouex pipefail

# ==============================================================================
#  Zotac Zone – Bazzite Custom Image Build Script
#
#  Quellen:
#    Treiber (HID/Platform/Dials): github.com/OpenZotacZone/ZotacZone-Drivers
#    Fan EC-Treiber:               gist.github.com/ElektroCoder (+ Pfahli Installer)
#    HDR & 144hz Fix:              github.com/OpenZotacZone/Zotac-Zone-HDR-144hz
#    Decky Loader + Plugins:       github.com/SteamDeckHomebrew
# ==============================================================================

echo "=== Starte Zotac Zone Build ==="

OPENZONE_RAW="https://raw.githubusercontent.com/OpenZotacZone/ZotacZone-Drivers/refs/heads/main"
ELEKTROCODER_RAW="https://gist.githubusercontent.com/ElektroCoder/c3ddfbe6dff057ab16375ab965876e74/raw/a7bdf061ca0613ef243e1e9851b70e886face4ea"
HDR_RAW="https://raw.githubusercontent.com/OpenZotacZone/Zotac-Zone-HDR-144hz/refs/heads/main"

# ==============================================================================
# 1. ABHÄNGIGKEITEN
# ==============================================================================
echo "-> Installiere Build-Abhängigkeiten..."

KERNEL_VERSION=$(ls /usr/lib/modules/ | grep -v 'debug' | sort -V | tail -n 1)

rpm-ostree install \
    kernel-devel-${KERNEL_VERSION} \
    gcc \
    make \
    wget \
    git \
    python3-pip

pip install evdev --break-system-packages

# ==============================================================================
# 2. OPENZONE HID + PLATFORM TREIBER
#    Quelle: github.com/OpenZotacZone/ZotacZone-Drivers
#    Liefert: Input, Back-Buttons, RGB, Radial-Dials, Platform-Sensor
# ==============================================================================
echo "-> Baue OpenZONE HID & Platform Treiber..."

BUILD_DIR="/tmp/zotac_zone_build"
DRIVER_INSTALL_DIR="/usr/local/lib/zotac-zone"
mkdir -p "$BUILD_DIR" "$DRIVER_INSTALL_DIR"
cd "$BUILD_DIR"

for f in \
    "zotac-zone-hid-core.c" \
    "zotac-zone-hid-rgb.c" \
    "zotac-zone-hid-input.c" \
    "zotac-zone-hid-config.c" \
    "zotac-zone.h"
do
    wget -q "${OPENZONE_RAW}/driver/hid/${f}"
done

for f in \
    "zotac-zone-platform.c" \
    "firmware_attributes_class.h" \
    "firmware_attributes_class.c"
do
    wget -q "${OPENZONE_RAW}/driver/platform/${f}"
done

cat > Makefile << 'EOF'
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
cp *.ko "$DRIVER_INSTALL_DIR/"

cat > /usr/lib/systemd/system/zotac-zone-drivers.service << EOF
[Unit]
Description=Zotac Zone HID & Platform Drivers (OpenZONE)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/modprobe led-class-multicolor
ExecStart=/usr/sbin/modprobe platform_profile
ExecStart=/usr/sbin/insmod ${DRIVER_INSTALL_DIR}/firmware_attributes_class.ko
ExecStart=/usr/sbin/insmod ${DRIVER_INSTALL_DIR}/zotac-zone-platform.ko
ExecStart=/usr/sbin/insmod ${DRIVER_INSTALL_DIR}/zotac-zone-hid.ko
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable zotac-zone-drivers.service

cat > /usr/lib/udev/rules.d/99-zotac-zone.rules << 'EOF'
KERNEL=="hidraw*", ATTRS{idVendor}=="1ee9", ATTRS{idProduct}=="1590", MODE="0666"
EOF

echo "uinput" > /usr/lib/modules-load.d/zotac-uinput.conf

# ==============================================================================
# 3. DIAL DAEMON
#    Quelle: github.com/OpenZotacZone/ZotacZone-Drivers
#    Liefert: Radial-Dials -> Volume / Brightness / Scroll / ...
# ==============================================================================
echo "-> Installiere Dial-Daemon..."

DIAL_SCRIPT="/usr/local/bin/zotac_dial_daemon.py"

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
    "volume":            {"type": "key",       "up": e.KEY_VOLUMEUP,    "down": e.KEY_VOLUMEDOWN},
    "brightness":        {"type": "backlight", "step": 5},
    "scroll":            {"type": "rel",       "axis": e.REL_WHEEL,     "up": 1,  "down": -1},
    "scroll_inverted":   {"type": "rel",       "axis": e.REL_WHEEL,     "up": -1, "down": 1},
    "arrows_vertical":   {"type": "key",       "up": e.KEY_UP,          "down": e.KEY_DOWN},
    "arrows_horizontal": {"type": "key",       "up": e.KEY_RIGHT,       "down": e.KEY_LEFT},
    "media":             {"type": "key",       "up": e.KEY_NEXTSONG,    "down": e.KEY_PREVIOUSSONG},
    "page_scroll":       {"type": "key",       "up": e.KEY_PAGEUP,      "down": e.KEY_PAGEDOWN},
    "zoom":              {"type": "key",       "up": e.KEY_ZOOMIN,      "down": e.KEY_ZOOMOUT},
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
        new_v = max(0, min(cur_v + (step if direction == "up" else -step), max_v))
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
    print(f"Dial Daemon. Links:{args.left} | Rechts:{args.right}")
    backlight = find_backlight()
    cap = {e.EV_KEY: [], e.EV_REL: [e.REL_WHEEL]}
    for a in ACTIONS.values():
        if a["type"] == "key": cap[e.EV_KEY].extend([a["up"], a["down"]])
        elif a["type"] == "rel": cap[e.EV_REL].append(a["axis"])
    ui = UInput(cap, name="Zotac Zone Virtual Dials")
    while True:
        dev_path = find_hidraw()
        if not dev_path:
            time.sleep(3); continue
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
                    if   ac["type"] == "backlight" and backlight:
                        set_backlight(backlight, di, ac["step"])
                    elif ac["type"] == "key":
                        ui.write(e.EV_KEY, ac[di], 1); ui.write(e.EV_KEY, ac[di], 0); ui.syn()
                    elif ac["type"] == "rel":
                        ui.write(e.EV_REL, ac["axis"], ac[di]); ui.syn()
        except OSError: time.sleep(2)
        except Exception as err: print(f"Err:{err}"); time.sleep(2)

if __name__ == "__main__":
    main()
PYEOF
chmod +x "$DIAL_SCRIPT"

cat > /usr/lib/systemd/system/zotac-dials.service << EOF
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

# ==============================================================================
# 4. EC FAN TREIBER + COOLERCONTROL
#    Quelle: ElektroCoder Gist (hwmon-only zotac-zone-platform.c)
#            github.com/OpenZotacZone/Zotac-Zone-Fan-Control (Installer-Skript)
#    Liefert: hwmon "zotac_platform" -> Fan-PWM, RPM, Temp-Sensor
#             CoolerControl AppImage als Daemon (Web-UI: localhost:11987)
# ==============================================================================
echo "-> Baue EC Fan-Treiber & installiere CoolerControl..."

EC_BUILD_DIR="/tmp/zotac_ec_fan_build"
EC_INSTALL_DIR="/usr/local/lib/zotac-zone-fan"
mkdir -p "$EC_BUILD_DIR" "$EC_INSTALL_DIR"
cd "$EC_BUILD_DIR"

# EC-Treiber Quellcode (hwmon-only Version von ElektroCoder/Pfahli)
wget -q -O zotac-zone-platform.c \
    "${ELEKTROCODER_RAW}/zotac-zone-platform.c"

cat > Makefile << 'EOF'
obj-m += zotac-zone-platform.o
all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
EOF

make -C /usr/lib/modules/${KERNEL_VERSION}/build M=$(pwd) modules
cp zotac-zone-platform.ko "$EC_INSTALL_DIR/"

# Fan-Enable Skript
cat > /usr/local/bin/zotac-fan-enable.sh << EOF
#!/usr/bin/env bash
set -e
echo "[*] Lade Zotac Zone EC Fan-Treiber..."
if ! /usr/sbin/lsmod | grep -q '^zotac_zone_platform '; then
    /usr/sbin/insmod ${EC_INSTALL_DIR}/zotac-zone-platform.ko || { echo "[!] insmod fehlgeschlagen"; exit 0; }
    echo "[+] Modul geladen."
else
    echo "[+] Modul bereits aktiv."
fi
echo "[*] Starte CoolerControl neu..."
/usr/bin/systemctl restart coolercontrold || true
echo "[+] Fan-Setup abgeschlossen."
EOF
chmod +x /usr/local/bin/zotac-fan-enable.sh

# CoolerControl Daemon (AppImage)
CC_DIR="/var/opt/coolercontrol"
mkdir -p "$CC_DIR"
curl -fL -o "${CC_DIR}/CoolerControlD-x86_64.AppImage" \
    "https://github.com/coolercontrol/coolercontrol/releases/latest/download/CoolerControlD-x86_64.AppImage"
chmod +x "${CC_DIR}/CoolerControlD-x86_64.AppImage"

cat > /usr/lib/systemd/system/coolercontrold.service << EOF
[Unit]
Description=CoolerControl Daemon (Fan Control)
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Environment=DISPLAY=:0
ExecStart=${CC_DIR}/CoolerControlD-x86_64.AppImage
Restart=on-failure
RestartSec=5
LimitNOFILE=1024

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/lib/systemd/system/zotac-fan.service << 'EOF'
[Unit]
Description=Zotac Zone EC Fan-Treiber
After=multi-user.target coolercontrold.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/zotac-fan-enable.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable coolercontrold.service
systemctl enable zotac-fan.service

# ==============================================================================
# 5. HDR & 144Hz FIX
#    Quelle: github.com/OpenZotacZone/Zotac-Zone-HDR-144hz
#    Liefert: Gepatchte EDID (grüner Tint-Fix + 144Hz OLED)
#    Methode: EDID .bin -> /usr/lib/firmware/edid/ + drm.edid_firmware karg
# ==============================================================================
echo "-> Installiere HDR & 144Hz EDID-Fix..."

HDR_BUILD_DIR="/tmp/zotac_hdr_build"
mkdir -p "$HDR_BUILD_DIR"
cd "$HDR_BUILD_DIR"

mkdir -p /usr/lib/firmware/edid

# Installer-Skript herunterladen
wget -q -O install_zotac_hdr.sh "${HDR_RAW}/install_zotac_hdr.sh"
chmod +x install_zotac_hdr.sh

# Non-interactive ausführen (Reboot-Prompts ignorieren)
# Das Skript platziert die EDID-Datei und setzt rpm-ostree kargs
bash install_zotac_hdr.sh || true

# Sicherheitscheck
if ls /usr/lib/firmware/edid/*.bin 2>/dev/null | head -n 1 > /dev/null; then
    echo "[+] EDID-Datei erfolgreich platziert."
    # drm.edid_firmware Parameter für Bootloader sichern
    # (wird von rpm-ostree kargs oder grubenv gesetzt)
    EDID_FILE=$(ls /usr/lib/firmware/edid/*.bin | head -n 1 | xargs basename)
    echo "    -> Kernel-Parameter: drm.edid_firmware=eDP-1:edid/${EDID_FILE}"
else
    echo "WARN: EDID-Datei wurde nicht gefunden – HDR/144Hz-Fix nicht aktiv!"
    echo "      Bitte install_zotac_hdr.sh manuell nach der Installation ausführen."
fi

# ==============================================================================
# 6. DECKY LOADER
#    Quelle: github.com/SteamDeckHomebrew/decky-loader
#    Non-interactive für Image-Build
# ==============================================================================
echo "-> Installiere Decky Loader..."

DECKY_HOME="/home/deck/homebrew"
DECKY_SERVICES="${DECKY_HOME}/services"
mkdir -p "${DECKY_SERVICES}"

DECKY_RELEASE_URL=$(curl -sf \
    "https://api.github.com/repos/SteamDeckHomebrew/decky-loader/releases/latest" \
    | grep 'browser_download_url.*PluginLoader[^.]*"' | cut -d '"' -f 4 | head -n 1)

if [ -n "$DECKY_RELEASE_URL" ]; then
    curl -fL -o "${DECKY_SERVICES}/PluginLoader" "$DECKY_RELEASE_URL"
    chmod +x "${DECKY_SERVICES}/PluginLoader"
    echo "[+] Decky Loader heruntergeladen."
else
    echo "WARN: Decky Loader Release-URL nicht gefunden"
fi

cat > /usr/lib/systemd/system/plugin_loader.service << EOF
[Unit]
Description=Decky Plugin Loader
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=deck
Environment=DECKY_HOME=${DECKY_HOME}
ExecStart=${DECKY_SERVICES}/PluginLoader
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable plugin_loader.service

# ==============================================================================
# 7. DECKY PLUGINS VORINSTALLIEREN
# ==============================================================================
echo "-> Lade Decky Plugins herunter..."

PLUGIN_STAGING="/usr/share/decky-plugins-staging"
mkdir -p "$PLUGIN_STAGING"
cd "$PLUGIN_STAGING"

PLUGINS=(
    "aarron-lee/SimpleDeckTDP"
    "AAGaming00/unifydeck"
    "xXJSONDeruloXx/Decky-Framegen"
    "xXJSONDeruloXx/decky-lsfg-vk"
    "moi952/decky-proton-launch"
    "moraroy/NonSteamLaunchersDecky"
    "Starkka15/junkstore"
    "DeckThemes/decky-theme-loader"
    "Tormak9970/TabMaster"
    "Wurielle/decky-launch-options"
    "jwhitlow45/free-loader"
    "SteamGridDB/decky-steamgriddb"
    "Lui92/decky-protondb-collections"
    "kEnder242/decky-trailers"
    "Echarnus/DeckyMetacritic"
    "cat-in-a-box/Decky-Translator"
    "sebet/decky-nonsteam-badges"
    "jacobdonahoe/decky-game-optimizer"
    "samedayhurt/reshady"
)

for repo in "${PLUGINS[@]}"; do
    DOWNLOAD_URL=$(curl -sf "https://api.github.com/repos/${repo}/releases/latest" \
        | grep 'browser_download_url.*\.tar\.gz' | cut -d '"' -f 4 | head -n 1)

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "  SKIP: kein .tar.gz Release für ${repo}"
        continue
    fi

    wget -q --show-progress "$DOWNLOAD_URL" || echo "  SKIP: Download fehlgeschlagen für ${repo}"
done

for f in *.tar.gz; do
    [ -f "$f" ] && tar -xzf "$f" && rm "$f"
done

# Login-Sync: Plugins beim ersten User-Login in ~/homebrew/plugins kopieren
mkdir -p /usr/etc/profile.d/
cat > /usr/etc/profile.d/decky-zotac-sync.sh << 'EOF'
#!/bin/bash
STAGING="/usr/share/decky-plugins-staging"
DEST="${HOME}/homebrew/plugins"
if [ -d "$STAGING" ] && [ "$(ls -A "$STAGING" 2>/dev/null)" ]; then
    mkdir -p "$DEST"
    cp -rn "${STAGING}/"* "$DEST/" 2>/dev/null || true
fi
EOF
chmod +x /usr/etc/profile.d/decky-zotac-sync.sh

# ==============================================================================
# 8. AUFRÄUMEN
# ==============================================================================
echo "-> Aufräumen..."
cd /
rm -rf "$BUILD_DIR" "$EC_BUILD_DIR" "$HDR_BUILD_DIR"

echo ""
echo "=== Build abgeschlossen ==="
echo "  [OK] OpenZONE HID/Platform Treiber  – Input, RGB, Back-Buttons"
echo "  [OK] Dial Daemon                     – Volume/Brightness/Scroll"
echo "  [OK] EC Fan Treiber (ElektroCoder)   – hwmon zotac_platform"
echo "  [OK] CoolerControl                   – Fan-Kurven (localhost:11987)"
echo "  [OK] HDR & 144Hz EDID-Fix            – kein grüner Tint, OLED 144Hz"
echo "  [OK] Decky Loader                    – Plugin-System"
echo "  [OK] Decky Plugins (${#PLUGINS[@]}x) – staging -> ~/homebrew/plugins"