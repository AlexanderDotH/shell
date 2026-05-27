pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

Scope {
    id: root

    readonly property string primaryMonitor: Quickshell.env("CAELESTIA_PRIMARY_MONITOR") || "DP-1"

    // Destroy layer-shell windows entirely so nothing can stay stuck on screen.
    property bool active: Quickshell.env("CAELESTIA_DISABLE_STARTUP_SPLASH") !== "1"

    Component.onCompleted: {
        if (root.active)
            dismissTimer.start();
    }

    Timer {
        id: dismissTimer

        interval: 1200
        onTriggered: root.active = false
    }

    LazyLoader {
        active: root.active

        SplashScreens {
            primaryMonitor: root.primaryMonitor
            primaryName: "startup-splash"
            secondaryName: "startup-splash-black"
            animateDismiss: false
            message: qsTr("Starting…")
            indicatorRunning: true
        }
    }
}
