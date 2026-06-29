import Caelestia.Config
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    property string message: qsTr("Starting…")
    property bool indicatorRunning: true
    property bool animateEntrance: false

    // Black until scheme.json is applied — no default-palette flash.
    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Loader {
        id: themedLoader

        anchors.fill: parent
        active: Colours.schemeReady
        asynchronous: false
        onLoaded: {
            if (root.animateEntrance)
                item.entranceAnim.start();

        }

        sourceComponent: Item {
            id: themedRoot

            property alias entranceAnim: entranceAnim

            Rectangle {
                anchors.fill: parent
                color: Colours.palette.m3surface
            }

            ColumnLayout {
                id: content

                anchors.centerIn: parent
                spacing: Tokens.spacing.large * 2
                opacity: root.animateEntrance ? 0 : 1
                scale: root.animateEntrance ? 0.85 : 1

                Item {
                    id: logoWrap

                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 128
                    Layout.preferredHeight: 90
                    transformOrigin: Item.Center

                    Logo {
                        anchors.fill: parent
                    }

                }

                StyledText {
                    id: statusText

                    Layout.alignment: Qt.AlignHCenter
                    opacity: root.animateEntrance ? 0 : 1
                    text: root.message
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }

                CircularIndicator {
                    id: spinner

                    Layout.alignment: Qt.AlignHCenter
                    opacity: root.animateEntrance ? 0 : 1
                    running: root.indicatorRunning
                    implicitSize: Tokens.font.body.medium.pointSize * 3
                    fgColour: Colours.palette.m3primary
                    bgColour: Colours.palette.m3secondaryContainer
                }

            }

            ParallelAnimation {
                id: entranceAnim

                Anim {
                    target: content
                    properties: "opacity,scale"
                    from: 0
                    to: 1
                    type: Anim.DefaultSpatial
                }

                SequentialAnimation {
                    Anim {
                        target: logoWrap
                        property: "scale"
                        from: 0.7
                        to: 1
                        type: Anim.FastSpatial
                    }

                    Anim {
                        target: statusText
                        property: "opacity"
                        from: 0
                        to: 1
                        type: Anim.StandardLarge
                    }

                    Anim {
                        target: spinner
                        property: "opacity"
                        from: 0
                        to: 1
                        type: Anim.StandardLarge
                    }

                }

            }

        }

    }

}
