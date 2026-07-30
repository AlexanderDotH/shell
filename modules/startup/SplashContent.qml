pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    property bool animateEntrance: false
    property bool indicatorRunning: true
    property string message: qsTr("Starting…")

    // Black until scheme.json is applied — no default-palette flash.
    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Loader {
        id: themedLoader

        active: Colours.schemeReady
        anchors.fill: parent
        asynchronous: false

        sourceComponent: Item {
            id: themedRoot

            Component.onCompleted: {
                if (root.animateEntrance)
                    entranceAnim.start();
            }

            Rectangle {
                anchors.fill: parent
                color: Colours.palette.m3surface
            }

            ColumnLayout {
                id: content

                anchors.centerIn: parent
                opacity: root.animateEntrance ? 0 : 1
                scale: root.animateEntrance ? 0.85 : 1
                spacing: Tokens.spacing.large * 2

                Item {
                    id: logoWrap

                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: 90
                    Layout.preferredWidth: 128
                    transformOrigin: Item.Center

                    Logo {
                        anchors.fill: parent
                    }
                }

                StyledText {
                    id: statusText

                    Layout.alignment: Qt.AlignHCenter
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                    opacity: root.animateEntrance ? 0 : 1
                    text: root.message
                }

                CircularIndicator {
                    id: spinner

                    Layout.alignment: Qt.AlignHCenter
                    bgColour: Colours.palette.m3secondaryContainer
                    fgColour: Colours.palette.m3primary
                    implicitSize: Tokens.font.body.medium.pointSize * 3
                    opacity: root.animateEntrance ? 0 : 1
                    running: root.indicatorRunning
                }
            }

            ParallelAnimation {
                id: entranceAnim

                Anim {
                    from: 0
                    properties: "opacity,scale"
                    target: content
                    to: 1
                    type: Anim.DefaultSpatial
                }

                SequentialAnimation {
                    Anim {
                        from: 0.7
                        property: "scale"
                        target: logoWrap
                        to: 1
                        type: Anim.FastSpatial
                    }

                    Anim {
                        from: 0
                        property: "opacity"
                        target: statusText
                        to: 1
                        type: Anim.StandardLarge
                    }

                    Anim {
                        from: 0
                        property: "opacity"
                        target: spinner
                        to: 1
                        type: Anim.StandardLarge
                    }
                }
            }
        }
    }
}
