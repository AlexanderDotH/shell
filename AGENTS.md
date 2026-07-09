## Learned User Preferences

- Uses paru (not yay) as AUR helper on Arch Linux
- Requires sudo for system package installs on Arch
- Prefers cmake install to user paths (`INSTALL_QSCONFDIR`, `INSTALL_LIBDIR`, `CAELESTIA_LIB_DIR` under `$HOME`) rather than overwriting `/usr` or `/etc/xdg`
- Do not overwrite `~/.config/caelestia/shell.json` when installing or updating the shell

## Learned Workspace Facts

- Runs Caelestia shell (Quickshell) on Hyprland on Arch Linux
- Custom fork at https://github.com/AlexanderDotH/shell, cloned to `/home/alex/Workspace/Projects/QML/shell`
- Caelestia QML config installed to `~/.config/quickshell/caelestia` (overrides AUR `/etc/xdg/quickshell/caelestia`)
- User theme/settings live in `~/.config/caelestia/shell.json`
- 3-monitor Hyprland layout (HDMI-A-1, DP-2, DP-1); watchdog sets `CAELESTIA_EXPECTED_MONITORS=3`
- Watchdog script at `~/.config/hypr/scripts/run-caelestia-watchdog.sh` starts `qs -c caelestia`
- Native libs install to `~/.local/lib/caelestia`; Qt QML plugin to `~/.local/lib/qt6/qml`
- Quickshell crash logs at `~/.cache/quickshell/crashes/`
