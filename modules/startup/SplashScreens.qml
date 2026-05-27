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
    property bool animateDismiss: true
    property string message: qsTr("Starting…")
    property bool indicatorRunning: true

    readonly property bool windowVisible: !root.dismissing || (root.animateDismiss && windowOpacity > 0.01)

    readonly property real windowOpacity: root.dismissing ? 0 : 1

    Variants {
        model: Screens.screens.filter(s => s.name === root.primaryMonitor)

        StyledWindow {
            required property ShellScreen modelData

            screen: modelData
            name: root.primaryName
            visible: root.windowVisible
            opacity: root.windowOpacity

            Behavior on opacity {
                enabled: root.animateDismiss

                NumberAnimation {
                    duration: 380
                    easing.type: Easing.OutCubic
                }
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            color: Colours.tPalette.m3surface

            SplashContent {
                anchors.fill: parent
                message: root.message
                indicatorRunning: root.indicatorRunning
            }
        }
    }

    Variants {
        model: Screens.screens.filter(s => s.name !== root.primaryMonitor)

        StyledWindow {
            required property ShellScreen modelData

            screen: modelData
            name: root.secondaryName
            visible: root.windowVisible
            opacity: root.windowOpacity

            Behavior on opacity {
                enabled: root.animateDismiss

                NumberAnimation {
                    duration: 380
                    easing.type: Easing.OutCubic
                }
            }

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
