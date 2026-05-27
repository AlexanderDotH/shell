pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import qs.components.containers
import qs.services

Scope {
    id: root

    readonly property string primaryMonitor: Quickshell.env("CAELESTIA_PRIMARY_MONITOR") || "DP-1"

    Variants {
        model: Screens.screens.filter(s => s.name === root.primaryMonitor)

        StyledWindow {
            required property ShellScreen modelData

            screen: modelData
            name: "boot-splash"
            visible: true

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            color: Colours.tPalette.m3surface

            SplashContent {
                anchors.fill: parent
                message: qsTr("Starting shell…")
                indicatorRunning: true
            }
        }
    }
}
