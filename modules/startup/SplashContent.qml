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

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Tokens.spacing.large * 2

        Logo {
            Layout.alignment: Qt.AlignHCenter
            width: 128
            height: 90
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.message
            color: Colours.tPalette.m3onSurfaceVariant
            font.pointSize: Tokens.font.size.normal
        }

        CircularIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: root.indicatorRunning
            implicitSize: Tokens.font.size.normal * 3
            fgColour: Colours.palette.m3primary
            bgColour: Colours.palette.m3secondaryContainer
        }
    }
}
