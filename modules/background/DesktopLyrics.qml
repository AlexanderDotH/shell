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

    required property real absX
    required property real absY
    readonly property real backgroundOpacity: Math.max(0, Math.min(Config.background.desktopLyrics.background.opacity, 1))
    readonly property bool bgEnabled: Config.background.desktopLyrics.background.enabled
    readonly property bool blurEnabled: bgEnabled && Config.background.desktopLyrics.background.blur && !GameMode.enabled
    readonly property bool enabledByConfig: GlobalConfig.background.desktopLyrics.enabled && Config.background.desktopLyrics.enabled
    readonly property string lyricFontFamily: "Rubik"
    readonly property real lyricFontPointSize: Tokens.font.headline.medium.pointSize * 1.15 * root.lyricScale
    readonly property real lyricHorizontalInset: Math.max(Tokens.padding.large * root.lyricScale, 28 * root.lyricScale)
    readonly property real lyricLineGap: Tokens.spacing.large * 2.7 * lyricScale
    readonly property real lyricRowHeight: lyricMetrics.height * root.maxLyricTextScale + root.lyricLineGap
    readonly property real lyricScale: Config.background.desktopLyrics.scale
    readonly property real lyricSolidness: root.bgEnabled ? Math.max(0, Math.min((root.backgroundOpacity - 0.85) / 0.15, 1)) : 1
    readonly property bool lyricsActuallyVisible: enabledByConfig && Lyrics.hasLyrics && playbackAllowsLyrics
    readonly property real maxLyricTextScale: 1.14
    readonly property real musicLineHeight: Math.max(root.lyricRowHeight * 0.9, 54 * root.lyricScale)
    readonly property bool playbackAllowsLyrics: !!Players.active && (Config.background.desktopLyrics.showWhilePaused || Players.active.isPlaying)
    readonly property int visibleLineCount: 5
    required property Item wallpaper

    implicitHeight: root.visibleLineCount * root.lyricRowHeight + (root.bgEnabled ? Tokens.padding.large * 4 : 0)
    opacity: lyricsActuallyVisible ? 1 : 0
    visible: lyricsActuallyVisible || hideTimer.running

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
        interval: GlobalConfig.dashboard.mediaUpdateInterval
        repeat: true
        running: root.lyricsActuallyVisible && !!Players.active && Players.active.isPlaying
        triggeredOnStart: true

        onTriggered: Players.active?.positionChanged()
    }

    FontMetrics {
        id: lyricMetrics

        font.family: root.lyricFontFamily
        font.pointSize: root.lyricFontPointSize
        font.weight: Font.Bold
    }

    Loader {
        active: root.blurEnabled
        anchors.fill: parent
        asynchronous: true

        sourceComponent: MultiEffect {
            autoPaddingEnabled: false
            blur: 1
            blurEnabled: true
            blurMax: 64
            maskEnabled: true
            maskSource: backgroundPlate

            source: ShaderEffectSource {
                sourceItem: root.wallpaper
                sourceRect: Qt.rect(root.absX, root.absY, root.width, root.height)
            }
        }
    }

    StyledRect {
        id: backgroundPlate

        anchors.fill: parent
        color: Colours.palette.m3surface
        layer.enabled: root.blurEnabled
        opacity: root.backgroundOpacity
        radius: Tokens.rounding.large * root.lyricScale
        visible: root.bgEnabled
    }

    StyledListView {
        id: lyricsView

        property real currentLineEndProgress: 0
        property real currentTargetY: originY
        property bool frameSyncActive: false
        readonly property real frameSyncStartProgress: 0.68
        property real nextTargetY: originY

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

        function clampedContentY(value: real): real {
            const minY = originY;
            const maxY = Math.max(minY, originY + contentHeight - height);
            return Math.max(minY, Math.min(value, maxY));
        }

        function contentCenterYForIndex(index: int): real {
            const item = itemAtIndex(index);
            if (!item)
                return contentY + height / 2;

            return item.y + item.height / 2;
        }

        function currentLineColor(): color {
            return mixColor(Colours.palette.m3primary, normalLineColor(), currentLineEndProgress);
        }

        function currentLineGlowOpacity(): real {
            return 0.38 * (1 - currentLineEndProgress);
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

        function currentLineScale(): real {
            return root.maxLyricTextScale - (root.maxLyricTextScale - 1) * currentLineEndProgress;
        }

        function easeOutCubic(value: real): real {
            const progress = Math.max(0, Math.min(value, 1));
            return 1 - Math.pow(1 - progress, 3);
        }

        function hasActiveTimelineMotion(): bool {
            if (!root.lyricsActuallyVisible || !Players.active?.isPlaying || currentIndex < 0 || currentIndex >= count - 1)
                return false;

            const progress = currentLineProgress();
            const scrollProgress = nextLineProgress();

            return progress >= frameSyncStartProgress || (scrollProgress > 0 && scrollProgress < 1);
        }

        function inactiveLineColor(distance: int): color {
            const normalizedDistance = Math.max(1, distance);
            const nearGrey = mixColor(Colours.palette.m3outline, Colours.palette.m3onSurfaceVariant, 0.28 * root.lyricSolidness);
            return mixColor(nearGrey, Colours.palette.m3outline, Math.min((normalizedDistance - 1) / 3, 1));
        }

        function inactiveLineOpacity(distance: int): real {
            const normalizedDistance = Math.max(1, distance);
            const nearOpacity = 0.68 + 0.16 * root.lyricSolidness;
            const floorOpacity = 0.12 + 0.06 * root.lyricSolidness;

            return Math.max(floorOpacity, nearOpacity - (normalizedDistance - 1) * 0.22);
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

        function mixColor(from: color, to: color, amount: real): color {
            const t = Math.max(0, Math.min(amount, 1));
            return Qt.rgba(from.r + (to.r - from.r) * t, from.g + (to.g - from.g) * t, from.b + (to.b - from.b) * t, from.a + (to.a - from.a) * t);
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

        function normalLineColor(): color {
            return mixColor(Colours.palette.m3onSurfaceVariant, Colours.palette.m3onSurface, root.lyricSolidness);
        }

        function refreshTimeline(forcePositioning: bool): void {
            syncToTimeline(forcePositioning);
            frameSyncActive = hasActiveTimelineMotion();
        }

        function smoothstep(value: real): real {
            const progress = Math.max(0, Math.min(value, 1));
            return progress * progress * (3 - 2 * progress);
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

        function updateLineTargets(forcePositioning: bool): void {
            currentTargetY = centeredContentYForIndex(currentIndex, forcePositioning, forcePositioning);
            nextTargetY = currentIndex < count - 1 ? centeredContentYForIndex(currentIndex + 1, false, false) : currentTargetY;
        }

        anchors.fill: parent
        anchors.margins: root.bgEnabled ? Tokens.padding.large * 2 : 0
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: height * 4
        clip: true
        currentIndex: Lyrics.indexForTime(Players.active?.position ?? 0)
        highlightFollowsCurrentItem: false
        interactive: false
        layer.enabled: true
        model: Lyrics.lyrics

        delegate: Item {
            id: delegateRoot

            readonly property real baseHeight: hasContent ? contentHeight + root.lyricLineGap : 0
            readonly property real contentHeight: isMusicCue ? Math.max(root.musicLineHeight, lyricText.contentHeight * root.maxLyricTextScale) : lyricText.contentHeight * root.maxLyricTextScale
            readonly property bool hasContent: lyricLine && lyricLine.trim().length > 0
            required property int index
            readonly property bool isCurrent: ListView.isCurrentItem
            readonly property bool isMusicCue: lyricLine.trim() === "\u266a"
            readonly property int lineDistance: lyricsView.currentIndex < 0 ? 3 : Math.abs(index - lyricsView.currentIndex)
            readonly property string lyricLine: modelData ?? ""
            readonly property real lyricOpacity: showMusicAnimation ? 0 : isCurrent ? 1 : lyricsView.inactiveLineOpacity(lineDistance)
            required property string modelData
            readonly property bool showMusicAnimation: isMusicCue && isCurrent

            height: baseHeight
            width: ListView.view.width

            MultiEffect {
                anchors.fill: lyricText
                autoPaddingEnabled: true
                blur: 0.35
                blurEnabled: true
                enabled: delegateRoot.isCurrent && !delegateRoot.showMusicAnimation
                opacity: lyricText.opacity
                scale: lyricText.scale
                shadowBlur: 0.7
                shadowColor: Colours.palette.m3primary
                shadowEnabled: true
                shadowHorizontalOffset: 0
                shadowOpacity: lyricsView.currentLineGlowOpacity()
                shadowVerticalOffset: 0
                source: lyricText
                visible: delegateRoot.isCurrent && !delegateRoot.showMusicAnimation
            }

            Text {
                id: lyricText

                anchors.horizontalCenter: parent.horizontalCenter
                color: delegateRoot.isCurrent ? lyricsView.currentLineColor() : lyricsView.inactiveLineColor(delegateRoot.lineDistance)
                font.family: root.lyricFontFamily
                font.hintingPreference: Font.PreferNoHinting
                font.pointSize: root.lyricFontPointSize
                font.weight: delegateRoot.isCurrent ? Font.Bold : Font.Medium
                horizontalAlignment: Text.AlignHCenter
                opacity: delegateRoot.lyricOpacity
                renderType: Text.CurveRendering
                scale: delegateRoot.isCurrent ? lyricsView.currentLineScale() : Math.max(0.86, 1 - delegateRoot.lineDistance * 0.04)
                text: delegateRoot.lyricLine ? delegateRoot.lyricLine.replace(/\u00A0/g, " ") : ""
                visible: opacity > 0.01
                width: Math.max(1, (parent.width - root.lyricHorizontalInset * 2) / root.maxLyricTextScale)
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                y: Math.max(0, (delegateRoot.baseHeight - height) / 2)

                Behavior on color {
                    CAnim {
                        duration: Tokens.anim.durations.small
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: Tokens.anim.durations.normal
                        easing: Tokens.anim.standard
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

                readonly property real barGap: Math.max(3, 6 * root.lyricScale)
                readonly property real barWidth: Math.max(3, 4 * root.lyricScale)

                anchors.horizontalCenter: parent.horizontalCenter
                enabled: false
                height: root.musicLineHeight
                opacity: delegateRoot.showMusicAnimation ? 1 : 0
                visible: opacity > 0.01
                width: barContent.width
                y: Math.max(0, (delegateRoot.baseHeight - height) / 2)

                Behavior on opacity {
                    NumberAnimation {
                        duration: Tokens.anim.durations.normal
                        easing: Tokens.anim.standard
                    }
                }

                Item {
                    id: barContent

                    anchors.centerIn: parent
                    height: Math.max(16, 24 * root.lyricScale)
                    width: 5 * musicAnimation.barWidth + 4 * musicAnimation.barGap

                    Repeater {
                        model: 5

                        StyledRect {
                            id: bar

                            readonly property real highHeight: Math.max(10, (14 + (index + 1) % 3 * 3) * root.lyricScale)
                            required property int index
                            readonly property real lowHeight: Math.max(4, (5 + index % 2) * root.lyricScale)

                            anchors.bottom: barContent.bottom
                            antialiasing: true
                            color: index % 3 === 0 ? Colours.palette.m3primary : index % 3 === 1 ? Colours.palette.m3secondary : Colours.palette.m3tertiary
                            height: lowHeight
                            opacity: 0.78
                            radius: width / 2
                            width: musicAnimation.barWidth
                            x: index * (musicAnimation.barWidth + musicAnimation.barGap)

                            SequentialAnimation on height {
                                loops: Animation.Infinite
                                running: musicAnimation.visible && !!Players.active && Players.active.isPlaying

                                PauseAnimation {
                                    duration: bar.index * 70
                                }

                                NumberAnimation {
                                    duration: 360 + bar.index * 45
                                    easing.type: Easing.InOutSine
                                    to: bar.highHeight
                                }

                                NumberAnimation {
                                    duration: 420 + bar.index * 35
                                    easing.type: Easing.InOutSine
                                    to: bar.lowHeight
                                }
                            }
                        }
                    }
                }
            }
        }
        layer.effect: Mask {
            maskSource: fadeMask

            Rectangle {
                id: fadeMask

                implicitHeight: lyricsView.height
                implicitWidth: lyricsView.width
                layer.enabled: true
                visible: false

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

        onCurrentIndexChanged: {
            if (root.lyricsActuallyVisible && currentIndex >= 0)
                Qt.callLater(() => refreshTimeline(true));
        }
        onHeightChanged: {
            if (root.lyricsActuallyVisible && currentIndex >= 0)
                Qt.callLater(() => refreshTimeline(true));
        }
        onModelChanged: {
            if (model && model.count > 0 && currentIndex >= 0)
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
    }

    Timer {
        id: hideTimer

        interval: 300
        repeat: false
    }
}
