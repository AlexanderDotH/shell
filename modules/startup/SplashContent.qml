import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    property string message: qsTr("Starting…")
    property bool indicatorRunning: true
    property bool dismissing: false

    ColumnLayout {
        id: content

        anchors.centerIn: parent
        spacing: Tokens.spacing.large * 2
        opacity: 0
        scale: 0

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 128
            Layout.preferredHeight: 90

            id: logoWrap

            rotation: 180
            transformOrigin: Item.Center

            Logo {
                anchors.fill: parent
            }

            SequentialAnimation {
                running: root.indicatorRunning && !root.dismissing
                loops: Animation.Infinite

                NumberAnimation {
                    target: logoWrap
                    property: "opacity"
                    from: 0.82
                    to: 1
                    duration: Tokens.anim.durations.large
                    easing.type: Easing.InOutSine
                }

                NumberAnimation {
                    target: logoWrap
                    property: "opacity"
                    from: 1
                    to: 0.82
                    duration: Tokens.anim.durations.large
                    easing.type: Easing.InOutSine
                }
            }
        }

        StyledText {
            id: statusText

            Layout.alignment: Qt.AlignHCenter
            opacity: 0
            text: root.message
            color: Colours.tPalette.m3onSurfaceVariant
            font.pointSize: Tokens.font.size.normal
        }

        CircularIndicator {
            id: spinner

            Layout.alignment: Qt.AlignHCenter
            opacity: 0
            running: root.indicatorRunning
            implicitSize: Tokens.font.size.normal * 3
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
            ParallelAnimation {
                Anim {
                    target: logoWrap
                    property: "rotation"
                    from: 180
                    to: 360
                    duration: Tokens.anim.durations.expressiveFastSpatial
                    easing: Tokens.anim.standardAccel
                }

                Anim {
                    target: logoWrap
                    property: "scale"
                    from: 0.65
                    to: 1
                    type: Anim.FastSpatial
                }
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

    Component.onCompleted: entranceAnim.start()

    ParallelAnimation {
        id: exitAnim

        running: root.dismissing

        Anim {
            target: content
            property: "opacity"
            to: 0
            type: Anim.StandardSmall
        }

        Anim {
            target: content
            property: "scale"
            to: 0.88
            type: Anim.FastSpatial
        }

        onFinished: content.visible = false
    }
}
