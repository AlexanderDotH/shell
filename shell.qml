//@ pragma Env QS_CRASHREPORT_URL=https://github.com/caelestia-dots/shell/issues/new?template=crash.yml
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma DefaultEnv QS_DROP_EXPENSIVE_FONTS=1
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
//@ pragma DefaultEnv QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import QtQuick
import "modules"
import "modules/drawers"
import "modules/background"
import "modules/areapicker"
import "modules/lock"
import Quickshell
import Quickshell.Hyprland

ShellRoot {
    id: root

    settings.watchFiles: true

    readonly property int expectedMonitors: parseInt(Quickshell.env("CAELESTIA_EXPECTED_MONITORS") || "3")
    readonly property bool monitorsReady: Hyprland.monitors.values.length >= expectedMonitors

    Loader {
        active: root.monitorsReady

        sourceComponent: Item {
            Background {}
            Drawers {}
        }
    }

    AreaPicker {}
    Lock {
        id: lock
    }

    ConfigToasts {}
    Shortcuts {}
    BatteryMonitor {}
    IdleMonitors {
        lock: lock
    }
}
