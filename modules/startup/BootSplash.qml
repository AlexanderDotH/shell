pragma ComponentBehavior: Bound

import Quickshell
import qs.services

Scope {
    SplashScreens {
        primaryName: "boot-splash"
        animateEntrance: true
        message: qsTr("Starting shell…")
        indicatorRunning: true
    }
}
