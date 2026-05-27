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

    Rectangle {
        anchors.fill: parent
        color: Colours.tPalette.m3surface
    }

    ColumnLayout {
        id: content

        anchors.centerIn: parent
        spacing: Tokens.spacing.large * 2
        opacity: 0
        scale: 0.85

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 128
            Layout.preferredHeight: 90

            id: logoWrap

            transformOrigin: Item.Center

            Logo {
                anchors.fill: parent
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

    Component.onCompleted: entranceAnim.start()
}
