# OpenZotacZone Bazzite Image for the Zotac Zone Handheld

Dieses Projekt baut ein **angepasstes** Bazzite-Image für das Zotac Zone Gaming Handheld mit integrierten OpenZotacZone-Treibern, 144‑Hz- und HDR-Fixes, verbessertem Lüfterverhalten sowie vorinstalliertem Decky Loader mit kuratierter Plugin-Auswahl.[page:1]

## Warum dieses Image?

OpenZotacZone-Treiber, die über `build.sh` oder manuelle Skripte installiert werden, sind nur temporär und müssen nach Kernel-Updates neu gebaut und erneut installiert werden.[page:1]  
Ein benutzerdefiniertes Bazzite-basiertes Image macht diese Treiber persistent – sie überstehen Systemupdates, Reboots und Rebases innerhalb des Universal Blue / bootc Workflows.[page:1]

## Basis

- Zotac-spezifische Anpassungen: https://github.com/Reed-Schimmel/ZotacBazzite [page:1]  
- Offizielles Universal Blue Image-Template: https://github.com/ublue-os/image-template [page:1]

## Features

- Integrierte OpenZotacZone-Treiber, fest im Image eingebunden und automatisch beim Boot geladen.[page:1]  
- Zotac-Zone-spezifische Funktionen:
  - Back Buttons voll funktionsfähig (P4/P3-like).[page:1]
  - RGB-Beleuchtung steuerbar über OpenRGB.[page:1]
  - Lüfterkurven (EC Fan Control) verwaltet über CoolerControl.[page:1]
  - Joystick-Dials mit präziser Eingabe durch Rotation und Druck.[page:1]
  - Erweiterte HID-Protokoll-Unterstützung.[page:1]
  - Touchpad-Tweaks für präzisere Eingaben.[page:1]
- Display & Gaming:
  - HDR-Fix-Skripte für zuverlässigere HDR-Aktivierung in unterstützten Spielen.[page:1]
  - 144‑Hz-Fixes (X11/Wayland-Konfiguration + Gamescope/KWin-Tuning), damit das Panel stabil mit 144 Hz läuft.[page:1]
- Komfort:
  - Vorinstallierter Decky Loader mit ausgewählten Plugins.[page:1]

## Build-Hinweis

Vor dem Rebuild: `iso-gnome.toml` oder `iso-kde.toml` in `iso.toml` umbenennen, committen und anschließend das Image neu bauen
