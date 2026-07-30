pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Scope {
    id: root

    property bool active: Quickshell.env("CAELESTIA_DISABLE_STARTUP_SPLASH") !== "1"
    property bool minShowElapsed: false
    property bool forceDismiss: false

    readonly property bool shouldDismiss: root.active && (root.minShowElapsed || root.forceDismiss)

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
        onTriggered: {
            splashScreens.dismissing = true;
            hideSplashTimer.start();
        }
    }

    Timer {
        id: hideSplashTimer

        interval: 450
        repeat: false
        onTriggered: root.active = false
    }

    // Live on Quickshell.screens — new outputs get a splash as they appear.
    SplashScreens {
        id: splashScreens

        visible: root.active
        animateEntrance: true
        message: qsTr("Starting…")
        indicatorRunning: true
    }
}
