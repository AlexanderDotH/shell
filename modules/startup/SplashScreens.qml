pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components.containers
import qs.services

Scope {
    id: root

    property string primaryName: "startup-splash"
    property bool dismissing: false
    property bool animateDismiss: false
    property string message: qsTr("Starting…")
    property bool indicatorRunning: true
    property bool animateEntrance: false
    property bool visible: true

    Variants {
        // Rebinds when monitors hotplug without retaining null/dangling placeholders.
        model: Screens.validScreens

        StyledWindow {
            required property ShellScreen modelData

            screen: modelData
            name: `${root.primaryName}-${modelData.name}`
            visible: root.visible && !root.dismissing

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            color: "black"

            SplashContent {
                anchors.fill: parent
                animateEntrance: root.animateEntrance
                message: root.message
                indicatorRunning: root.indicatorRunning
            }
        }
    }
}
