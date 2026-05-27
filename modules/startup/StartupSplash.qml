pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

Scope {
    id: root

    readonly property string primaryMonitor: Quickshell.env("CAELESTIA_PRIMARY_MONITOR") || "DP-1"
    readonly property int expectedMonitors: parseInt(Quickshell.env("CAELESTIA_EXPECTED_MONITORS") || "3")
    property bool dismissing: false
    property bool minShowElapsed: false
    property bool forceDismiss: false

    readonly property int monitorCount: Math.max(Hyprland.monitors.values.length, Quickshell.screens.length)

    readonly property bool monitorsReady: root.monitorCount >= root.expectedMonitors

    readonly property bool shouldDismiss: !root.dismissing && root.minShowElapsed && (root.monitorsReady || root.forceDismiss)

    function dismiss(): void {
        if (root.dismissing)
            return;
        root.dismissing = true;
    }

    Component.onCompleted: minShowTimer.start()

    Timer {
        id: minShowTimer

        interval: 700
        onTriggered: root.minShowElapsed = true
    }

    Timer {
        interval: 5000
        running: !root.dismissing
        repeat: false
        onTriggered: root.forceDismiss = true
    }

    Timer {
        interval: 450
        running: root.shouldDismiss
        repeat: false
        onTriggered: root.dismiss()
    }

    SplashScreens {
        primaryMonitor: root.primaryMonitor
        primaryName: "startup-splash"
        secondaryName: "startup-splash-black"
        dismissing: root.dismissing
        animateDismiss: true
        message: qsTr("Starting…")
        indicatorRunning: !root.dismissing
    }
}
