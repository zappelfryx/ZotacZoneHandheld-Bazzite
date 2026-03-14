# OpenZotacZone Bazzite Image for the Zotac Zone Handheld

This project builds a **custom** Bazzite image for the Zotac Zone gaming handheld with integrated OpenZotacZone drivers, 144 Hz and HDR fixes, improved fan control, and a preinstalled Decky Loader with a curated plugin set.[page:2]

## Why this image?

OpenZotacZone drivers installed via `build.sh` or manual scripts are only temporary and need to be rebuilt and reinstalled after kernel updates.
A custom Bazzite-based image makes these drivers persistent – they survive system updates, reboots, and rebases within the Universal Blue / bootc workflow.

## Based on

- Zotac-specific adjustments: [https://github.com/Reed-Schimmel/ZotacBazzite](https://github.com/Reed-Schimmel/ZotacBazzite)  
- Official Universal Blue image template: [https://github.com/ublue-os/image-template](https://github.com/ublue-os/image-template)

## Features

- Integrated OpenZotacZone drivers, baked into the image and automatically loaded on boot.
- Zotac Zone–specific functionality:
  - Fully functional back buttons (P4/P3-like).
  - RGB lighting controllable via OpenRGB.
  - Fan curves (EC fan control) managed via CoolerControl.
  - Joystick dials with precise input via rotation and press.
  - Extended HID protocol support.
  - Touchpad tweaks for more precise input.
  - HDR fix scripts for more reliable HDR activation in supported games
  - 144 Hz fixes (X11/Wayland configuration + Gamescope/KWin tuning) so the panel runs consistently at 144 Hz.
- Convenience:
  - Preinstalled Decky Loader & plugins

## Build note

Before rebuilding: rename `iso-gnome.toml` or `iso-kde.toml` to `iso.toml`, commit the change, then rebuild the image.
