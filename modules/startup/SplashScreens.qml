pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
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

    property bool hidden: false

    readonly property bool windowVisible: !root.hidden

    readonly property real windowOpacity: root.dismissing ? 0 : 1

    readonly property list<ShellScreen> splashScreens: Screens.screens.length > 0 ? Screens.screens : Quickshell.screens

    onDismissingChanged: {
        if (root.dismissing)
            hideTimer.restart();
    }

    Timer {
        id: hideTimer

        interval: root.animateDismiss ? 420 : 0
        onTriggered: root.hidden = true
    }

    Variants {
        model: root.splashScreens.filter(s => s.name === root.primaryMonitor)

        StyledWindow {
            required property ShellScreen modelData

            screen: modelData
            name: root.primaryName
            visible: root.windowVisible

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            color: "transparent"

            Item {
                anchors.fill: parent
                opacity: root.windowOpacity
                visible: root.windowVisible

                Behavior on opacity {
                    enabled: root.animateDismiss

                    NumberAnimation {
                        duration: 380
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    id: surfaceBg

                    anchors.fill: parent
                    opacity: root.dismissing ? 0 : surfaceOpacity
                    color: Colours.tPalette.m3surface

                    property real surfaceOpacity: 0

                    Anim {
                        running: !root.dismissing
                        target: surfaceBg
                        property: "surfaceOpacity"
                        from: 0
                        to: 1
                        type: Anim.StandardLarge
                    }
                }

                SplashContent {
                    anchors.fill: parent
                    dismissing: root.dismissing
                    message: root.message
                    indicatorRunning: root.indicatorRunning
                }
            }
        }
    }

    Variants {
        model: root.splashScreens.filter(s => s.name !== root.primaryMonitor)

        StyledWindow {
            required property ShellScreen modelData

            screen: modelData
            name: root.secondaryName
            visible: root.windowVisible

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            color: "transparent"

            Rectangle {
                anchors.fill: parent
                opacity: root.windowOpacity
                visible: root.windowVisible
                color: "black"

                Behavior on opacity {
                    enabled: root.animateDismiss

                    NumberAnimation {
                        duration: 380
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}
