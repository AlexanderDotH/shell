pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components.containers
import qs.services

Scope {
    id: root

    required property string primaryMonitor
    property string primaryName: "splash-primary"
    property string secondaryName: "splash-secondary"
    property bool dismissing: false
    property bool animateDismiss: false
    property string message: qsTr("Starting…")
    property bool indicatorRunning: true

    readonly property list<ShellScreen> splashScreens: Quickshell.screens.length > 0 ? Quickshell.screens : Screens.screens

    Variants {
        model: root.splashScreens.filter(s => s.name === root.primaryMonitor)

        StyledWindow {
            required property ShellScreen modelData

            screen: modelData
            name: root.primaryName
            visible: true

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            color: "black"

            SplashContent {
                anchors.fill: parent
                dismissing: root.dismissing
                message: root.message
                indicatorRunning: root.indicatorRunning
            }
        }
    }

    Variants {
        model: root.splashScreens.filter(s => s.name !== root.primaryMonitor)

        StyledWindow {
            required property ShellScreen modelData

            screen: modelData
            name: root.secondaryName
            visible: true

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            color: "black"
        }
    }
}
