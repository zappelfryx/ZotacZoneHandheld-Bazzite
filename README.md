OpenZotacZone Bazzite Image for the Zotac Zone Handheld
This project builds a custom Bazzite image for the Zotac Zone gaming handheld with integrated OpenZotacZone drivers, 144 Hz & HDR fixes, improved fan control, and a preinstalled Decky Loader with a curated plugin set.

Why this image?
OpenZotacZone drivers installed via build.sh or manual scripts are only temporary: after kernel updates they must be rebuilt and reinstalled.

A custom Bazzite-based image makes these drivers persistent – they survive system updates, reboots, and rebases within the Universal Blue / bootc workflow.

Built upon:
Zotac-specific adjustments from: https://github.com/Reed-Schimmel/ZotacBazzite
The official Universal Blue image template: https://github.com/ublue-os/image-template
​
Image Features:
Integrated OpenZotacZone Drivers
OpenZotacZone drivers are baked into the image and loaded automatically on boot.
Zotac Zone specific features enabled:
Back buttons
Fully functional (P4/P3-like)
Configurable via Steam Input.
RGB lighting
Controllable via OpenRGB or an integrated lighting daemon, depending on configuration.
Fan curves (EC fan control)
Managed via CoolerControl with hardware-aware rules for quieter or more aggressive profiles.
Joystick dials
Precise input via rotation and press, ideal for menus, emulators, and shortcuts.
Extended HID protocol support so the dials show up properly in the system.
Additional improvements


rename iso-gnome or iso-kde.toml -> iso.toml > commit > rebuild
Touchpad tweaks for more precise input.
HDR fix scripts for more reliable HDR activation in supported games.
144 Hz fixes (X11/Wayland config + Gamescope/KWin tuning) so the panel consistently runs at 144 Hz.

Decky Loader & preinstalled plugins
