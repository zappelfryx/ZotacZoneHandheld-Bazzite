#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y tmux 

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket

echo "=== Installiere OpenZotacZone Treiber ==="
mkdir -p /tmp/zotac-drivers && cd /tmp/zotac-drivers

# ==========================================
# 1. Zotac Zone HDR & 144Hz Fix
# ==========================================
echo "-> Richte HDR & 144Hz EDID ein..."
git clone https://github.com/OpenZotacZone/Zotac-Zone-HDR-144hz.git
cd Zotac-Zone-HDR-144hz

# Container-sicher: Wir kopieren die EDID-Dateien direkt ins System-Firmware-Verzeichnis,
# anstatt das Skript auszuführen, welches versuchen würde, den aktiven Bootloader zu manipulieren.
mkdir -p /usr/lib/firmware/edid
cp *.bin /usr/lib/firmware/edid/ 2>/dev/null || true
cd ..

# ==========================================
# 2. Zotac Zone Fan Control (CoolerControl + Kernel Modul)
# ==========================================
echo "-> Richte Fan Control ein..."
git clone https://github.com/OpenZotacZone/Zotac-Zone-Fan-Control.git
cd Zotac-Zone-Fan-Control

# A. CoolerControl installieren (in erlaubten Pfad /usr/libexec statt /var/opt)
mkdir -p /usr/libexec/coolercontrol
curl -L -o /usr/libexec/coolercontrol/CoolerControlD-x86_64.AppImage "https://github.com/coolercontrol/coolercontrol/releases/latest/download/CoolerControlD-x86_64.AppImage"
chmod +x /usr/libexec/coolercontrol/CoolerControlD-x86_64.AppImage

# B. Systemd Service sicher anlegen (ohne ihn sofort starten zu wollen)
cat << 'EOF' > /usr/lib/systemd/system/coolercontrold.service
[Unit]
Description=CoolerControl Daemon
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/libexec/coolercontrol/CoolerControlD-x86_64.AppImage
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable coolercontrold.service

# C. Das Zotac-Kernel-Modul bauen (Der wichtigste Trick!)
# Wir ermitteln die Kernel-Version des *Bazzite-Images*, nicht die des GitHub-Servers
KERNEL_VERSION=$(ls /usr/lib/modules/ | grep -v 'debug' | head -n 1)
echo "Baue Kernel-Modul für Bazzite-Kernel: $KERNEL_VERSION"

if [ -f "zotac-zone-platform.c" ]; then
    # Kompilieren mit dem korrekten Kernel-Pfad
    make -C /usr/lib/modules/$KERNEL_VERSION/build M=$(pwd) modules
    
    # Modul an den richtigen Ort kopieren
    mkdir -p /usr/lib/modules/$KERNEL_VERSION/extra/
    cp zotac-zone-platform.ko /usr/lib/modules/$KERNEL_VERSION/extra/
    
    # Sicherstellen, dass das Modul bei jedem Boot geladen wird
    echo "zotac-zone-platform" > /usr/lib/modules-load.d/zotac-zone-platform.conf
    depmod -a -b /usr $KERNEL_VERSION
fi
cd ..

# ==========================================
# 3. Zotac Zone Dial Drivers
# ==========================================
echo "-> Richte Dial Drivers ein..."
git clone https://github.com/OpenZotacZone/Zotac-Zone-Dial-Drivers.git
cd Zotac-Zone-Dial-Drivers

# Python-Skripte in einen sicheren Systemordner kopieren
mkdir -p /usr/libexec/zotac-dial
cp *.py /usr/libexec/zotac-dial/ 2>/dev/null || true

# Service-Datei anpassen (Pfade von /opt oder /var auf /usr umschreiben)
if [ -f "zotac-dial.service" ]; then
    sed -i 's|/opt/|/usr/libexec/|g' zotac-dial.service
    sed -i 's|/var/opt/|/usr/libexec/|g' zotac-dial.service
    cp zotac-dial.service /usr/lib/systemd/system/
    systemctl enable zotac-dial.service
fi
cd ..

# Aufräumen
rm -rf /tmp/zotac-drivers
echo "=== OpenZotacZone Treiber erfolgreich integriert ===”


