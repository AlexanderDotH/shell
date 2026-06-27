pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Wallpaper & style")

    function forEachDesktopLyricsConfig(callback: var): void {
        callback(GlobalConfig.background.desktopLyrics);
        for (const screen of Screens.screens)
            callback(GlobalConfig.forScreen(screen.name).background.desktopLyrics);
    }

    function setDesktopLyricsEnabled(enabled: bool): void {
        forEachDesktopLyricsConfig(config => {
            config.enabled = enabled;
        });
        if (enabled)
            Lyrics.refresh();
    }

    function setDesktopLyricsScale(scale: real): void {
        forEachDesktopLyricsConfig(config => {
            config.scale = scale;
        });
    }

    function setDesktopLyricsShowWhilePaused(showWhilePaused: bool): void {
        forEachDesktopLyricsConfig(config => {
            config.showWhilePaused = showWhilePaused;
        });
    }

    function setDesktopLyricsExcludedScreens(excludedScreens: var): void {
        forEachDesktopLyricsConfig(config => {
            config.excludedScreens = excludedScreens;
        });
    }

    function setDesktopLyricsMonitorEnabled(screenName: string, enabled: bool): void {
        const excludedScreens = (GlobalConfig.background.desktopLyrics.excludedScreens ?? []).slice();
        const index = excludedScreens.indexOf(screenName);
        if (enabled && index >= 0)
            excludedScreens.splice(index, 1);
        else if (!enabled && index < 0)
            excludedScreens.push(screenName);

        setDesktopLyricsExcludedScreens(excludedScreens);
    }

    function setDesktopLyricsBackgroundEnabled(enabled: bool): void {
        forEachDesktopLyricsConfig(config => {
            config.background.enabled = enabled;
        });
    }

    function setDesktopLyricsBackgroundBlur(blur: bool): void {
        forEachDesktopLyricsConfig(config => {
            config.background.blur = blur;
        });
    }

    function setDesktopLyricsBackgroundOpacity(opacity: real): void {
        forEachDesktopLyricsConfig(config => {
            config.background.opacity = opacity;
        });
    }

    function normalizedValue(value: real, from: real, to: real): real {
        return Math.max(0, Math.min((value - from) / (to - from), 1));
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledClippingRect {
            id: wallWrapper

            Layout.alignment: Qt.AlignHCenter
            implicitWidth: {
                const screen = root.nState.screen;
                return implicitHeight / screen.height * screen.width;
            }
            implicitHeight: {
                const screen = root.nState.screen;
                const cWidth = root.cappedWidth;
                return Math.min(Math.round(cWidth * 0.4), cWidth / screen.width * screen.height);
            }

            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.large

            Loader {
                anchors.centerIn: parent
                opacity: Config.background.wallpaperEnabled ? 0 : 1
                active: opacity > 0

                sourceComponent: ColumnLayout {
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hide_image"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Wallpaper disabled")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.large
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }
            }

            Item {
                anchors.fill: parent
                opacity: Config.background.wallpaperEnabled ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }

                Loader {
                    id: wallIndicatorLoader

                    anchors.centerIn: parent

                    opacity: 0
                    active: opacity > 0

                    sourceComponent: StyledRect {
                        implicitWidth: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2
                        implicitHeight: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2

                        color: Colours.palette.m3primaryContainer
                        radius: Tokens.rounding.full

                        LoadingIndicator {
                            id: wallLoadingIndicator

                            anchors.centerIn: parent
                            containsIcon: true
                            implicitSize: Math.min(wallWrapper.implicitWidth, wallWrapper.implicitHeight) * 0.4
                        }
                    }

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                Timer {
                    id: wallLoadDebounceTimer

                    interval: 100
                    onTriggered: {
                        if (wallImg.status !== Image.Ready)
                            wallIndicatorLoader.opacity = 1;
                    }
                }

                FadeImage {
                    id: wallImg

                    anchors.fill: parent
                    source: Wallpapers.current
                    preventInit: wallIndicatorLoader.opacity > 0
                    fadeOutAnim: Anim.DefaultEffects
                    fadeInAnim: Anim.SlowEffects

                    onSourceChanged: wallLoadDebounceTimer.restart()

                    onStatusChanged: {
                        if (status === Image.Ready) {
                            wallLoadDebounceTimer.stop();
                            wallIndicatorLoader.opacity = 0;
                        }
                    }
                }
            }
        }

        ButtonRow {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Tokens.spacing.large - parent.spacing
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "wallpaper"
                text: qsTr("Wallpapers")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                disabled: !Config.background.wallpaperEnabled
                onClicked: root.nState.openSubPage(1) // Wallpaper page
            }

            IconTextButton {
                icon: "palette"
                text: qsTr("Colours")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: root.nState.openSubPage(3) // Colours page
            }
        }

        ToggleRow {
            first: true
            text: qsTr("Display wallpaper")
            checked: Config.background.wallpaperEnabled
            onToggled: GlobalConfig.background.wallpaperEnabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            text: qsTr("Transparency")
            subtext: qsTr("Base %1, layers %2").arg(Colours.transparency.base).arg(Colours.transparency.layers)
            checked: Colours.transparency.enabled
            onToggled: GlobalConfig.appearance.transparency.enabled = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Dark theme")
            checked: !Colours.light
            onToggled: Colours.setMode(checked ? "dark" : "light")
        }

        SectionHeader {
            text: qsTr("Desktop lyrics")
        }

        ToggleRow {
            first: true
            text: qsTr("Show desktop lyrics")
            subtext: Lyrics.hasLyrics ? qsTr("%1 - %2").arg(Lyrics.trackArtist).arg(Lyrics.trackTitle) : qsTr("Synced lyrics over the wallpaper")
            checked: GlobalConfig.background.desktopLyrics.enabled
            onToggled: root.setDesktopLyricsEnabled(checked)
        }

        ToggleRow {
            text: qsTr("Show while paused")
            checked: GlobalConfig.background.desktopLyrics.showWhilePaused
            enabled: GlobalConfig.background.desktopLyrics.enabled
            onToggled: root.setDesktopLyricsShowWhilePaused(checked)
        }

        SliderRow {
            icon: "format_size"
            label: qsTr("Text scale")
            value: root.normalizedValue(GlobalConfig.background.desktopLyrics.scale, 0.6, 2)
            valueLabel: `${Math.round(GlobalConfig.background.desktopLyrics.scale * 100)}%`
            enabled: GlobalConfig.background.desktopLyrics.enabled
            onMoved: v => root.setDesktopLyricsScale(Math.round((0.6 + v * 1.4) * 100) / 100)
        }

        ToggleRow {
            text: qsTr("Background plate")
            checked: GlobalConfig.background.desktopLyrics.background.enabled
            enabled: GlobalConfig.background.desktopLyrics.enabled
            onToggled: root.setDesktopLyricsBackgroundEnabled(checked)
        }

        ToggleRow {
            text: qsTr("Blur behind lyrics")
            checked: GlobalConfig.background.desktopLyrics.background.blur
            enabled: GlobalConfig.background.desktopLyrics.enabled && GlobalConfig.background.desktopLyrics.background.enabled
            onToggled: root.setDesktopLyricsBackgroundBlur(checked)
        }

        SliderRow {
            icon: "opacity"
            label: qsTr("Plate opacity")
            value: GlobalConfig.background.desktopLyrics.background.opacity
            valueLabel: `${Math.round(GlobalConfig.background.desktopLyrics.background.opacity * 100)}%`
            enabled: GlobalConfig.background.desktopLyrics.enabled && GlobalConfig.background.desktopLyrics.background.enabled
            last: Screens.screens.length === 0
            onMoved: v => root.setDesktopLyricsBackgroundOpacity(Math.round(v * 100) / 100)
        }

        Repeater {
            model: Screens.screens

            ToggleRow {
                required property var modelData
                required property int index

                text: qsTr("Show on %1").arg(modelData.name)
                checked: !(GlobalConfig.background.desktopLyrics.excludedScreens ?? []).includes(modelData.name)
                enabled: GlobalConfig.background.desktopLyrics.enabled
                last: index === Screens.screens.length - 1
                onToggled: checked => root.setDesktopLyricsMonitorEnabled(modelData.name, checked)
            }
        }
    }
}
