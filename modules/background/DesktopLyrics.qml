pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.components.effects
import qs.services

Item {
    id: root

    required property Item wallpaper
    required property real absX
    required property real absY

    readonly property var _: {
        const player = Players.active;
        if (player)
            Lyrics.setTrack(player.trackArtist, player.trackTitle, player.trackAlbum, player.length);
        else
            Lyrics.clearTrack();
    }
    readonly property int visibleLineCount: 5
    readonly property real lyricScale: Config.background.desktopLyrics.scale
    readonly property real backgroundOpacity: Math.max(0, Math.min(Config.background.desktopLyrics.background.opacity, 1))
    readonly property real lyricSolidness: root.bgEnabled ? Math.max(0, Math.min((root.backgroundOpacity - 0.85) / 0.15, 1)) : 1
    readonly property real maxLyricTextScale: 1.14
    readonly property string lyricFontFamily: "Rubik"
    readonly property real lyricFontPointSize: Tokens.font.size.extraLarge * 1.15 * root.lyricScale
    readonly property real lyricHorizontalInset: Math.max(Tokens.padding.large * root.lyricScale, 28 * root.lyricScale)
    readonly property real lyricLineGap: Tokens.spacing.large * 2.7 * lyricScale
    readonly property real lyricRowHeight: lyricMetrics.height * root.maxLyricTextScale + root.lyricLineGap
    readonly property real musicLineHeight: Math.max(root.lyricRowHeight * 0.9, 54 * root.lyricScale)
    readonly property bool bgEnabled: Config.background.desktopLyrics.background.enabled
    readonly property bool blurEnabled: bgEnabled && Config.background.desktopLyrics.background.blur && !GameMode.enabled
    readonly property bool enabledByConfig: GlobalConfig.background.desktopLyrics.enabled && Config.background.desktopLyrics.enabled
    readonly property bool playbackAllowsLyrics: !!Players.active && (Config.background.desktopLyrics.showWhilePaused || Players.active.isPlaying)
    readonly property bool lyricsActuallyVisible: enabledByConfig && Lyrics.hasLyrics && playbackAllowsLyrics

    implicitHeight: root.visibleLineCount * root.lyricRowHeight + (root.bgEnabled ? Tokens.padding.large * 4 : 0)
    visible: lyricsActuallyVisible || hideTimer.running
    opacity: lyricsActuallyVisible ? 1 : 0

    onLyricsActuallyVisibleChanged: {
        if (lyricsActuallyVisible) {
            hideTimer.stop();
            Qt.callLater(() => lyricsView.refreshTimeline(true));
        } else {
            hideTimer.restart();
        }
    }

    Behavior on opacity {
        Anim {
            type: Anim.StandardLarge
        }
    }

    Timer {
        running: root.lyricsActuallyVisible && !!Players.active && Players.active.isPlaying
        interval: GlobalConfig.dashboard.mediaUpdateInterval
        triggeredOnStart: true
        repeat: true
        onTriggered: Players.active?.positionChanged()
    }

    FontMetrics {
        id: lyricMetrics

        font.family: root.lyricFontFamily
        font.pointSize: root.lyricFontPointSize
        font.weight: Font.Bold
    }

    Loader {
        asynchronous: true
        anchors.fill: parent
        active: root.blurEnabled

        sourceComponent: MultiEffect {
            source: ShaderEffectSource {
                sourceItem: root.wallpaper
                sourceRect: Qt.rect(root.absX, root.absY, root.width, root.height)
            }
            maskSource: backgroundPlate
            maskEnabled: true
            blurEnabled: true
            blur: 1
            blurMax: 64
            autoPaddingEnabled: false
        }
    }

    StyledRect {
        id: backgroundPlate

        visible: root.bgEnabled
        anchors.fill: parent
        radius: Tokens.rounding.large * root.lyricScale
        opacity: root.backgroundOpacity
        color: Colours.palette.m3surface

        layer.enabled: root.blurEnabled
    }

    StyledListView {
        id: lyricsView

        anchors.fill: parent
        anchors.margins: root.bgEnabled ? Tokens.padding.large * 2 : 0
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: false
        cacheBuffer: height * 4
        model: Lyrics.lyrics
        currentIndex: Lyrics.indexForTime(Players.active?.position ?? 0)
        highlightFollowsCurrentItem: false
        property real currentLineEndProgress: 0
        property real currentTargetY: originY
        property real nextTargetY: originY
        property bool frameSyncActive: false
        readonly property real frameSyncStartProgress: 0.68

        layer.enabled: true
        layer.effect: Mask {
            maskSource: fadeMask

            Rectangle {
                id: fadeMask

                layer.enabled: true
                visible: false
                implicitWidth: lyricsView.width
                implicitHeight: lyricsView.height

                gradient: Gradient {
                    orientation: Gradient.Vertical

                    GradientStop {
                        color: Qt.alpha("black", 0)
                        position: 0
                    }
                    GradientStop {
                        color: Qt.alpha("black", 1)
                        position: 0.18
                    }
                    GradientStop {
                        color: Qt.alpha("black", 1)
                        position: 0.82
                    }
                    GradientStop {
                        color: Qt.alpha("black", 0)
                        position: 1
                    }
                }
            }
        }

        function clampedContentY(value: real): real {
            const minY = originY;
            const maxY = Math.max(minY, originY + contentHeight - height);
            return Math.max(minY, Math.min(value, maxY));
        }

        function centeredContentYForIndex(index: int, allowPositioning: bool, forceRelayout: bool): real {
            if (forceRelayout)
                forceLayout();

            let item = itemAtIndex(index);
            if (!item && allowPositioning) {
                positionViewAtIndex(index, ListView.Center);
                forceLayout();
                item = itemAtIndex(index);
            }
            if (!item)
                return contentY;

            return clampedContentY(contentCenterYForIndex(index) - height / 2);
        }

        function contentCenterYForIndex(index: int): real {
            const item = itemAtIndex(index);
            if (!item)
                return contentY + height / 2;

            if (item.lyricCenterY !== undefined)
                return item.lyricCenterY;

            return item.y + item.height / 2;
        }

        function smoothstep(value: real): real {
            const progress = Math.max(0, Math.min(value, 1));
            return progress * progress * (3 - 2 * progress);
        }

        function easeOutCubic(value: real): real {
            const progress = Math.max(0, Math.min(value, 1));
            return 1 - Math.pow(1 - progress, 3);
        }

        function nextLineProgress(): real {
            if (!Players.active?.isPlaying || currentIndex < 0 || currentIndex >= count - 1)
                return 0;

            const currentTime = Lyrics.timeForIndex(currentIndex);
            const nextTime = Lyrics.timeForIndex(currentIndex + 1);
            if (currentTime < 0 || nextTime < 0)
                return 0;

            const duration = Math.max(0.1, nextTime - currentTime);
            const elapsed = Players.active.position - currentTime;

            return easeOutCubic((elapsed / duration - 0.72) / 0.24);
        }

        function currentLineProgress(): real {
            if (!Players.active?.isPlaying || currentIndex < 0 || currentIndex >= count - 1)
                return 0;

            const currentTime = Lyrics.timeForIndex(currentIndex);
            const nextTime = Lyrics.timeForIndex(currentIndex + 1);
            if (currentTime < 0 || nextTime < 0)
                return 0;

            const duration = Math.max(0.1, nextTime - currentTime);
            const elapsed = Players.active.position - currentTime;

            return Math.max(0, Math.min(elapsed / duration, 1));
        }

        function lineDurationForIndex(index: int): real {
            if (index < 0 || index >= count - 1)
                return 0;

            const currentTime = Lyrics.timeForIndex(index);
            const nextTime = Lyrics.timeForIndex(index + 1);
            if (currentTime < 0 || nextTime < 0)
                return 0;

            return Math.max(0, nextTime - currentTime);
        }

        function lineEndProgress(): real {
            return smoothstep((currentLineProgress() - 0.72) / 0.24);
        }

        function hasActiveTimelineMotion(): bool {
            if (!root.lyricsActuallyVisible || !Players.active?.isPlaying || currentIndex < 0 || currentIndex >= count - 1)
                return false;

            const progress = currentLineProgress();
            const scrollProgress = nextLineProgress();

            return progress >= frameSyncStartProgress || (scrollProgress > 0 && scrollProgress < 1);
        }

        function mixColor(from: color, to: color, amount: real): color {
            const t = Math.max(0, Math.min(amount, 1));
            return Qt.rgba(
                from.r + (to.r - from.r) * t,
                from.g + (to.g - from.g) * t,
                from.b + (to.b - from.b) * t,
                from.a + (to.a - from.a) * t
            );
        }

        function currentLineScale(): real {
            return root.maxLyricTextScale - (root.maxLyricTextScale - 1) * currentLineEndProgress;
        }

        function normalLineColor(): color {
            return mixColor(Colours.palette.m3onSurfaceVariant, Colours.palette.m3onSurface, root.lyricSolidness);
        }

        function inactiveLineColor(distance: int): color {
            const normalizedDistance = Math.max(1, distance);
            const nearGrey = mixColor(Colours.palette.m3outline, Colours.palette.m3onSurfaceVariant, 0.28 * root.lyricSolidness);
            return mixColor(nearGrey, Colours.palette.m3outline, Math.min((normalizedDistance - 1) / 3, 1));
        }

        function currentLineColor(): color {
            return mixColor(Colours.palette.m3primary, normalLineColor(), currentLineEndProgress);
        }

        function currentLineGlowOpacity(): real {
            return 0.38 * (1 - currentLineEndProgress);
        }

        function inactiveLineOpacity(distance: int): real {
            const normalizedDistance = Math.max(1, distance);
            const nearOpacity = 0.68 + 0.16 * root.lyricSolidness;
            const floorOpacity = 0.12 + 0.06 * root.lyricSolidness;

            return Math.max(floorOpacity, nearOpacity - (normalizedDistance - 1) * 0.22);
        }

        function updateLineTargets(forcePositioning: bool): void {
            currentTargetY = centeredContentYForIndex(currentIndex, forcePositioning, forcePositioning);
            nextTargetY = currentIndex < count - 1 ? centeredContentYForIndex(currentIndex + 1, false, false) : currentTargetY;
        }

        function syncToTimeline(forcePositioning: bool): void {
            if (!root.lyricsActuallyVisible || currentIndex < 0 || count === 0 || height <= 0) {
                currentLineEndProgress = 0;
                frameSyncActive = false;
                return;
            }

            if (forcePositioning)
                updateLineTargets(true);

            const targetY = currentTargetY + (nextTargetY - currentTargetY) * nextLineProgress();
            currentLineEndProgress = lineEndProgress();
            contentY = targetY;
        }

        function refreshTimeline(forcePositioning: bool): void {
            syncToTimeline(forcePositioning);
            frameSyncActive = hasActiveTimelineMotion();
        }

        onModelChanged: {
            if (model && model.count > 0 && currentIndex >= 0)
                Qt.callLater(() => refreshTimeline(true));
        }

        onCurrentIndexChanged: {
            if (root.lyricsActuallyVisible && currentIndex >= 0)
                Qt.callLater(() => refreshTimeline(true));
        }

        onHeightChanged: {
            if (root.lyricsActuallyVisible && currentIndex >= 0)
                Qt.callLater(() => refreshTimeline(true));
        }

        onWidthChanged: {
            if (root.lyricsActuallyVisible && currentIndex >= 0)
                Qt.callLater(() => refreshTimeline(true));
        }

        FrameAnimation {
            running: root.lyricsActuallyVisible && !!Players.active && Players.active.isPlaying && lyricsView.frameSyncActive
            onTriggered: lyricsView.refreshTimeline(false)
        }

        Timer {
            interval: 120
            repeat: true
            running: root.lyricsActuallyVisible && !!Players.active && Players.active.isPlaying && !lyricsView.frameSyncActive
            onTriggered: lyricsView.refreshTimeline(false)
        }

        delegate: Item {
            id: delegateRoot

            required property string modelData
            required property int index

            readonly property string lyricLine: modelData ?? ""
            readonly property bool isMusicCue: lyricLine.trim() === "\u266a"
            readonly property bool hasContent: lyricLine && lyricLine.trim().length > 0
            readonly property bool isCurrent: ListView.isCurrentItem
            readonly property bool showMusicAnimation: isMusicCue && isCurrent
            readonly property int lineDistance: lyricsView.currentIndex < 0 ? 3 : Math.abs(index - lyricsView.currentIndex)
            readonly property real contentHeight: isMusicCue ? Math.max(root.musicLineHeight, lyricText.contentHeight * root.maxLyricTextScale) : lyricText.contentHeight * root.maxLyricTextScale
            readonly property real baseHeight: hasContent ? contentHeight + root.lyricLineGap : 0
            readonly property real lyricCenterY: y + baseHeight / 2
            readonly property real lyricOpacity: showMusicAnimation ? 0 : isCurrent ? 1 : lyricsView.inactiveLineOpacity(lineDistance)

            width: ListView.view.width
            height: baseHeight

            MultiEffect {
                anchors.fill: lyricText
                source: lyricText
                scale: lyricText.scale
                enabled: delegateRoot.isCurrent && !delegateRoot.showMusicAnimation
                visible: delegateRoot.isCurrent && !delegateRoot.showMusicAnimation
                opacity: lyricText.opacity
                blurEnabled: true
                blur: 0.35
                shadowEnabled: true
                shadowColor: Colours.palette.m3primary
                shadowOpacity: lyricsView.currentLineGlowOpacity()
                shadowBlur: 0.7
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                autoPaddingEnabled: true
            }

            Text {
                id: lyricText

                text: delegateRoot.lyricLine ? delegateRoot.lyricLine.replace(/\u00A0/g, " ") : ""
                width: Math.max(1, (parent.width - root.lyricHorizontalInset * 2) / root.maxLyricTextScale)
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(0, (delegateRoot.baseHeight - height) / 2)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                renderType: Text.CurveRendering
                font.family: root.lyricFontFamily
                font.pointSize: root.lyricFontPointSize
                font.weight: delegateRoot.isCurrent ? Font.Bold : Font.Medium
                font.hintingPreference: Font.PreferNoHinting
                opacity: delegateRoot.lyricOpacity
                color: delegateRoot.isCurrent ? lyricsView.currentLineColor() : lyricsView.inactiveLineColor(delegateRoot.lineDistance)
                scale: delegateRoot.isCurrent ? lyricsView.currentLineScale() : Math.max(0.86, 1 - delegateRoot.lineDistance * 0.04)
                visible: opacity > 0.01

                Behavior on opacity {
                    NumberAnimation {
                        duration: Tokens.anim.durations.normal
                        easing: Tokens.anim.standard
                    }
                }

                Behavior on color {
                    CAnim {
                        duration: Tokens.anim.durations.small
                    }
                }

                Behavior on scale {
                    Anim {
                        type: Anim.DefaultSpatial
                    }
                }
            }

            Item {
                id: musicAnimation

                readonly property real barWidth: Math.max(3, 4 * root.lyricScale)
                readonly property real barGap: Math.max(3, 6 * root.lyricScale)

                width: barContent.width
                height: root.musicLineHeight
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(0, (delegateRoot.baseHeight - height) / 2)
                opacity: delegateRoot.showMusicAnimation ? 1 : 0
                visible: opacity > 0.01
                enabled: false

                Behavior on opacity {
                    NumberAnimation {
                        duration: Tokens.anim.durations.normal
                        easing: Tokens.anim.standard
                    }
                }

                Item {
                    id: barContent

                    width: 5 * musicAnimation.barWidth + 4 * musicAnimation.barGap
                    height: Math.max(16, 24 * root.lyricScale)
                    anchors.centerIn: parent

                    Repeater {
                        model: 5

                        StyledRect {
                            id: bar

                            required property int index

                            readonly property real lowHeight: Math.max(4, (5 + index % 2) * root.lyricScale)
                            readonly property real highHeight: Math.max(10, (14 + (index + 1) % 3 * 3) * root.lyricScale)

                            x: index * (musicAnimation.barWidth + musicAnimation.barGap)
                            anchors.bottom: barContent.bottom
                            width: musicAnimation.barWidth
                            height: lowHeight
                            radius: width / 2
                            antialiasing: true
                            opacity: 0.78
                            color: index % 3 === 0 ? Colours.palette.m3primary : index % 3 === 1 ? Colours.palette.m3secondary : Colours.palette.m3tertiary

                            SequentialAnimation on height {
                                running: musicAnimation.visible && !!Players.active && Players.active.isPlaying
                                loops: Animation.Infinite

                                PauseAnimation {
                                    duration: bar.index * 70
                                }

                                NumberAnimation {
                                    to: bar.highHeight
                                    duration: 360 + bar.index * 45
                                    easing.type: Easing.InOutSine
                                }

                                NumberAnimation {
                                    to: bar.lowHeight
                                    duration: 420 + bar.index * 35
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: hideTimer

        interval: 300
        repeat: false
    }
}
