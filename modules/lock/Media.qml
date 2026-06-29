import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.images
import qs.services

StyledClippingRect {
    id: root

    required property var lock

    readonly property bool hasArtworkColour: backgroundImage.status === Image.Ready && analyser.luminance > 0.02
    readonly property color artworkColour: hasArtworkColour ? accentFromArtwork(analyser.dominantColour) : Colours.palette.m3primary

    function accentFromArtwork(colour): color {
        const saturation = Math.max(0.42, colour.hslSaturation);
        const lightness = Colours.light ? 0.42 : 0.66;
        return Qt.hsla(colour.hslHue, saturation, lightness, 1);
    }

    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2
    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainer

    FadeImage {
        id: backgroundImage

        anchors.fill: parent
        source: Players.activeArtUrl

        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: {
            const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
            return Qt.size(width * dpr, height * dpr);
        }

        layer.enabled: true
        opacity: status === Image.Ready ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.StandardExtraLarge
            }
        }

        onSourceChanged: artworkAnalyserUpdate.restart()
        onStatusChanged: {
            if (status === Image.Ready)
                artworkAnalyserUpdate.restart();
        }
        onOpacityChanged: {
            if (status === Image.Ready && opacity >= 0.99)
                artworkAnalyserUpdate.restart();
        }
    }

    ImageAnalyser {
        id: analyser

        sourceItem: backgroundImage
        rescaleSize: 96
    }

    Timer {
        id: artworkAnalyserUpdate

        interval: 80
        onTriggered: analyser.requestUpdate()
    }

    StyledRect {
        anchors.fill: parent
        color: Colours.palette.m3surface
        opacity: backgroundImage.status === Image.Ready ? 0.7 : 0

        Behavior on opacity {
            Anim {
                type: Anim.StandardExtraLarge
            }
        }
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.padding.extraLarge
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.fillWidth: true
            animate: true
            text: (Players.active?.trackTitle ?? qsTr("Nothing playing")) || qsTr("Unknown track")
            color: root.artworkColour
            horizontalAlignment: Text.AlignHCenter
            font: Tokens.font.title.medium
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            animate: true
            text: (Players.active?.trackArtist ?? qsTr("Try playing some music!")) || qsTr("Unknown artist")
            color: Colours.palette.m3onSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            font: Tokens.font.body.small
            elide: Text.ElideRight
        }

        ButtonRow {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.medium

            spacing: Tokens.spacing.extraSmall

            IconButton {
                type: IconButton.Tonal
                icon: "skip_previous"
                isRound: true
                shapeMorph: true
                disabled: !Players.active?.canGoPrevious
                onClicked: Players.active?.previous()
            }

            IconButton {
                icon: Players.active?.isPlaying ? "pause" : "play_arrow"
                isRound: true
                shapeMorph: true
                checked: Players.active?.isPlaying ?? false
                disabled: !Players.active?.canTogglePlaying
                onClicked: Players.active?.togglePlaying()
                implicitWidth: implicitHeight + Tokens.padding.largeIncreased * 2
            }

            IconButton {
                type: IconButton.Tonal
                icon: "skip_next"
                isRound: true
                shapeMorph: true
                disabled: !Players.active?.canGoNext
                onClicked: Players.active?.next()
            }
        }
    }
}
