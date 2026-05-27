pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.components.containers
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

    Variants {
        model: Screens.screens.filter(s => s.name === root.primaryMonitor)

        StyledWindow {
            required property ShellScreen modelData

            screen: modelData
            name: "startup-splash"
            visible: !root.dismissing || opacity > 0.01
            opacity: root.dismissing ? 0 : 1

            Behavior on opacity {
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

            color: Colours.palette.m3surface

            Column {
                anchors.centerIn: parent
                spacing: 32

                Logo {
                    width: 128
                    height: 90
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Starting…")
                    font.pixelSize: 16
                    color: Colours.palette.m3onSurfaceVariant
                }

                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitWidth: 36
                    implicitHeight: 36
                    running: !root.dismissing
                }
            }
        }
    }
}
