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

    readonly property color artworkColour: hasArtworkColour ? accentFromArtwork(analyser.dominantColour) : Colours.palette.m3primary
    readonly property bool hasArtworkColour: backgroundImage.status === Image.Ready && analyser.luminance > 0.02
    required property var lock

    function accentFromArtwork(colour): color {
        const saturation = Math.max(0.42, colour.hslSaturation);
        const lightness = Colours.light ? 0.42 : 0.66;
        return Qt.hsla(colour.hslHue, saturation, lightness, 1);
    }

    color: Colours.tPalette.m3surfaceContainer
    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2
    radius: Tokens.rounding.extraLarge

    FadeImage {
        id: backgroundImage

        anchors.fill: parent
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        layer.enabled: true
        opacity: status === Image.Ready ? 1 : 0
        source: Players.activeArtUrl
        sourceSize: {
            const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
            return Qt.size(width * dpr, height * dpr);
        }

        onOpacityChanged: {
            if (status === Image.Ready && opacity >= 0.99)
                artworkAnalyserUpdate.restart();
        }
        onSourceChanged: artworkAnalyserUpdate.restart()
        onStatusChanged: {
            if (status === Image.Ready)
                artworkAnalyserUpdate.restart();
        }

        Behavior on opacity {
            Anim {
                type: Anim.StandardExtraLarge
            }
        }
    }

    ImageAnalyser {
        id: analyser

        rescaleSize: 96
        sourceItem: backgroundImage
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
        anchors.margins: Tokens.padding.extraLarge
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.fillWidth: true
            animate: true
            color: root.artworkColour
            elide: Text.ElideRight
            font: Tokens.font.title.medium
            horizontalAlignment: Text.AlignHCenter
            text: (Players.active?.trackTitle ?? qsTr("Nothing playing")) || qsTr("Unknown track")
        }

        StyledText {
            Layout.fillWidth: true
            animate: true
            color: Colours.palette.m3onSurfaceVariant
            elide: Text.ElideRight
            font: Tokens.font.body.small
            horizontalAlignment: Text.AlignHCenter
            text: (Players.active?.trackArtist ?? qsTr("Try playing some music!")) || qsTr("Unknown artist")
        }

        ButtonRow {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.extraSmall

            IconButton {
                disabled: !Players.active?.canGoPrevious
                icon: "skip_previous"
                isRound: true
                shapeMorph: true
                type: IconButton.Tonal

                onClicked: Players.active?.previous()
            }

            IconButton {
                checked: Players.active?.isPlaying ?? false
                disabled: !Players.active?.canTogglePlaying
                icon: Players.active?.isPlaying ? "pause" : "play_arrow"
                implicitWidth: implicitHeight + Tokens.padding.largeIncreased * 2
                isRound: true
                shapeMorph: true

                onClicked: Players.active?.togglePlaying()
            }

            IconButton {
                disabled: !Players.active?.canGoNext
                icon: "skip_next"
                isRound: true
                shapeMorph: true
                type: IconButton.Tonal

                onClicked: Players.active?.next()
            }
        }
    }
}
