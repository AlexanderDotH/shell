pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

Scope {
    id: root

    readonly property string primaryMonitor: Quickshell.env("CAELESTIA_PRIMARY_MONITOR") || "DP-1"

    property bool active: Quickshell.env("CAELESTIA_DISABLE_STARTUP_SPLASH") !== "1"

    readonly property int showMs: parseInt(Quickshell.env("CAELESTIA_SPLASH_SHOW_MS") || "3000")

    Component.onCompleted: {
        if (root.active)
            dismissTimer.start();
    }

    Timer {
        id: dismissTimer

        interval: root.showMs
        repeat: false
        onTriggered: root.active = false
    }

    LazyLoader {
        active: root.active

        SplashScreens {
            primaryMonitor: root.primaryMonitor
            primaryName: "startup-splash"
            secondaryName: "startup-splash-black"
            animateEntrance: true
            message: qsTr("Starting…")
            indicatorRunning: true
        }
    }
}
