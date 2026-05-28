pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

Scope {
    id: root

    readonly property int expectedMonitors: parseInt(Quickshell.env("CAELESTIA_EXPECTED_MONITORS") || "3")

    property bool active: Quickshell.env("CAELESTIA_DISABLE_STARTUP_SPLASH") !== "1"
    property bool minShowElapsed: false
    property bool forceDismiss: false

    readonly property int screenCount: Quickshell.screens.length

    readonly property bool screensReady: root.screenCount >= root.expectedMonitors

    readonly property bool shouldDismiss: root.active && root.minShowElapsed && (root.screensReady || root.forceDismiss)

    // Do not create layer windows until Quickshell has a screen object per output.
    readonly property bool canShow: root.active && root.screensReady

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
        interval: 400
        running: root.shouldDismiss
        repeat: false
        onTriggered: root.active = false
    }

    LazyLoader {
        active: root.canShow

        SplashScreens {
            animateEntrance: true
            message: qsTr("Starting…")
            indicatorRunning: true
        }
    }
}
