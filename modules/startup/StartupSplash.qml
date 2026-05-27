pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

Scope {
    id: root

    readonly property string primaryMonitor: Quickshell.env("CAELESTIA_PRIMARY_MONITOR") || "DP-1"
    readonly property int expectedMonitors: parseInt(Quickshell.env("CAELESTIA_EXPECTED_MONITORS") || "3")

    property bool active: Quickshell.env("CAELESTIA_DISABLE_STARTUP_SPLASH") !== "1"
    property bool minShowElapsed: false
    property bool forceDismiss: false

    readonly property int monitorCount: Math.max(Hyprland.monitors.values.length, Quickshell.screens.length)

    readonly property bool monitorsReady: root.monitorCount >= root.expectedMonitors

    readonly property bool shouldDismiss: root.active && root.minShowElapsed && (root.monitorsReady || root.forceDismiss)

    Component.onCompleted: {
        if (root.active)
            minShowTimer.start();
    }

    Timer {
        id: minShowTimer

        interval: 900
        onTriggered: root.minShowElapsed = true
    }

    Timer {
        interval: 8000
        running: root.active
        repeat: false
        onTriggered: root.forceDismiss = true
    }

    Timer {
        interval: 350
        running: root.shouldDismiss
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
