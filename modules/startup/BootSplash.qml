pragma ComponentBehavior: Bound

import Quickshell
import qs.services

Scope {
    readonly property string primaryMonitor: Quickshell.env("CAELESTIA_PRIMARY_MONITOR") || "DP-1"

    SplashScreens {
        primaryMonitor: root.primaryMonitor
        primaryName: "boot-splash"
        secondaryName: "boot-splash-black"
        animateDismiss: false
        message: qsTr("Starting shell…")
        indicatorRunning: true
    }
}
