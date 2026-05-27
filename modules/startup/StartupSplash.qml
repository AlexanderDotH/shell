pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

Scope {
    id: root

    readonly property string primaryMonitor: Quickshell.env("CAELESTIA_PRIMARY_MONITOR") || "DP-1"
    readonly property int expectedMonitors: parseInt(Quickshell.env("CAELESTIA_EXPECTED_MONITORS") || "3")
    property bool dismissing: false

    readonly property bool monitorsReady: Hyprland.monitors.values.length >= root.expectedMonitors

    function dismiss(): void {
        if (root.dismissing)
            return;
        root.dismissing = true;
    }

    Timer {
        interval: root.monitorsReady ? 0 : 450
        running: root.monitorsReady && !root.dismissing
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
