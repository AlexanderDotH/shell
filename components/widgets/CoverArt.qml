pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import M3Shapes
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.components.images
import qs.services

Item {
    id: root

    readonly property alias shape: shape
    readonly property bool hasArtworkColour: image.status === Image.Ready && analyser.luminance > 0.02
    readonly property color rawArtworkColour: analyser.dominantColour
    readonly property color artworkColour: hasArtworkColour ? root.accentFromArtwork(rawArtworkColour) : fallbackColour
    readonly property color onArtworkColour: Colours.on(artworkColour)

    property bool hadPrevious
    property color fallbackColour: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)

    function accentFromArtwork(colour): color {
        const saturation = Math.max(0.42, colour.hslSaturation);
        const lightness = Colours.light ? 0.42 : 0.66;
        return Qt.hsla(colour.hslHue, saturation, lightness, 1);
    }

    // Slight glow to separate from bg
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        blurMax: 1
        shadowColor: root.hasArtworkColour ? root.artworkColour : Colours.palette.m3outline
        shadowOpacity: root.hasArtworkColour ? 0.55 : 0.3
    }

    Behavior on fallbackColour {
        CAnim {}
    }

    Item {
        id: shapeWrapper

        anchors.fill: parent
        layer.enabled: true
        opacity: 1

        MaterialShape {
            id: shape

            anchors.fill: parent
            implicitSize: Math.min(root.width, root.height)
            shape: MaterialShape.Cookie12Sided
            color: Qt.alpha(root.artworkColour, 1)

            Anim on rotation {
                running: true
                paused: !Players.active?.isPlaying
                from: 360
                to: 0
                duration: 23500
                easing.type: Easing.Linear
                loops: Animation.Infinite
            }
        }
    }

    MaterialIcon {
        anchors.centerIn: parent

        grade: 200
        text: image.status === Image.Error ? "broken_image" : "art_track"
        color: Colours.palette.m3onSurfaceVariant
        fontStyle: Tokens.font.icon.size((parent.width * 0.35) || 1).build()
        opacity: image.status === Image.Null || image.status === Image.Error ? 1 : 0
        animate: true

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        anchors.centerIn: parent
        asynchronous: true
        active: opacity > 0
        opacity: image.status === Image.Loading ? 1 : 0

        sourceComponent: LoadingIndicator {
            implicitSize: root.width * 0.3
            color: Colours.palette.m3primaryContainer
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    FadeImage {
        id: image

        anchors.fill: parent

        source: Players.activeArtUrl

        layer.enabled: true
        layer.effect: Mask {
            maskSource: shapeWrapper
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

        sourceItem: image
        rescaleSize: 96
    }

    Timer {
        id: artworkAnalyserUpdate

        interval: 80
        onTriggered: analyser.requestUpdate()
    }
}
