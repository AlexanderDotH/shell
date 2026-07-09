pragma ComponentBehavior: Bound

import ".."
import "../appearance/sections"
import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

Item {
    id: root

    required property Session session

    property bool desktopClockEnabled: Config.background.desktopClock.enabled ?? false
    property real desktopClockScale: Config.background.desktopClock.scale ?? 1
    property string desktopClockPosition: Config.background.desktopClock.position ?? "bottom-right"
    property bool desktopClockShadowEnabled: Config.background.desktopClock.shadow.enabled ?? true
    property real desktopClockShadowOpacity: Config.background.desktopClock.shadow.opacity ?? 0.7
    property real desktopClockShadowBlur: Config.background.desktopClock.shadow.blur ?? 0.4
    property bool desktopClockBackgroundEnabled: Config.background.desktopClock.background.enabled ?? false
    property real desktopClockBackgroundOpacity: Config.background.desktopClock.background.opacity ?? 0.7
    property bool desktopClockBackgroundBlur: Config.background.desktopClock.background.blur ?? false
    property bool desktopClockInvertColors: Config.background.desktopClock.invertColors ?? false
    property bool desktopLyricsEnabled: GlobalConfig.background.desktopLyrics.enabled ?? false
    property real desktopLyricsScale: GlobalConfig.background.desktopLyrics.scale ?? 1
    property bool desktopLyricsShowWhilePaused: GlobalConfig.background.desktopLyrics.showWhilePaused ?? true
    property bool desktopLyricsBackgroundEnabled: GlobalConfig.background.desktopLyrics.background.enabled ?? false
    property real desktopLyricsBackgroundOpacity: GlobalConfig.background.desktopLyrics.background.opacity ?? 0.22
    property bool desktopLyricsBackgroundBlur: GlobalConfig.background.desktopLyrics.background.blur ?? true
    property list<string> desktopLyricsExcludedScreens: GlobalConfig.background.desktopLyrics.excludedScreens ?? []
    property list<string> monitorNames: Hypr.monitorNames()
    property string lyricsBackend: GlobalConfig.services.lyricsBackend ?? "Auto"
    property bool lyricsAsyncProviders: GlobalConfig.services.lyricsAsyncProviders ?? false
    property string lyricsNetEaseApiBase: GlobalConfig.services.lyricsNetEaseApiBase ?? "https://music.xianqiao.wang/neteaseapiv2"
    property string lyricsDeezerArl: GlobalConfig.services.lyricsDeezerArl ?? ""
    property string lyricsSpotifyAccessToken: GlobalConfig.services.lyricsSpotifyAccessToken ?? ""
    property string lyricsSpotifyClientId: GlobalConfig.services.lyricsSpotifyClientId ?? ""
    property string lyricsSpotifyClientSecret: GlobalConfig.services.lyricsSpotifyClientSecret ?? ""
    property bool backgroundEnabled: Config.background.enabled ?? true
    property bool wallpaperEnabled: Config.background.wallpaperEnabled ?? true
    property bool visualiserEnabled: Config.background.visualiser.enabled ?? false
    property bool visualiserAutoHide: Config.background.visualiser.autoHide ?? true
    property real visualiserRounding: Config.background.visualiser.rounding ?? 1
    property real visualiserSpacing: Config.background.visualiser.spacing ?? 1

    function applyDesktopLyricsConfig(desktopLyricsConfig: var): void {
        desktopLyricsConfig.enabled = root.desktopLyricsEnabled;
        desktopLyricsConfig.scale = root.desktopLyricsScale;
        desktopLyricsConfig.showWhilePaused = root.desktopLyricsShowWhilePaused;
        desktopLyricsConfig.excludedScreens = root.desktopLyricsExcludedScreens;
        desktopLyricsConfig.background.enabled = root.desktopLyricsBackgroundEnabled;
        desktopLyricsConfig.background.opacity = root.desktopLyricsBackgroundOpacity;
        desktopLyricsConfig.background.blur = root.desktopLyricsBackgroundBlur;
    }

    function setDesktopLyricsMonitorEnabled(screenName: string, enabled: bool): void {
        const excludedScreens = root.desktopLyricsExcludedScreens.slice();
        const index = excludedScreens.indexOf(screenName);

        if (enabled && index !== -1) {
            excludedScreens.splice(index, 1);
        } else if (!enabled && index === -1) {
            excludedScreens.push(screenName);
        }

        root.desktopLyricsExcludedScreens = excludedScreens;
        root.saveConfig();
    }

    function saveConfig() {
        GlobalConfig.background.enabled = root.backgroundEnabled;
        GlobalConfig.background.wallpaperEnabled = root.wallpaperEnabled;

        GlobalConfig.background.desktopClock.enabled = root.desktopClockEnabled;
        GlobalConfig.background.desktopClock.scale = root.desktopClockScale;
        GlobalConfig.background.desktopClock.position = root.desktopClockPosition;
        GlobalConfig.background.desktopClock.shadow.enabled = root.desktopClockShadowEnabled;
        GlobalConfig.background.desktopClock.shadow.opacity = root.desktopClockShadowOpacity;
        GlobalConfig.background.desktopClock.shadow.blur = root.desktopClockShadowBlur;
        GlobalConfig.background.desktopClock.background.enabled = root.desktopClockBackgroundEnabled;
        GlobalConfig.background.desktopClock.background.opacity = root.desktopClockBackgroundOpacity;
        GlobalConfig.background.desktopClock.background.blur = root.desktopClockBackgroundBlur;
        GlobalConfig.background.desktopClock.invertColors = root.desktopClockInvertColors;

        root.applyDesktopLyricsConfig(GlobalConfig.background.desktopLyrics);
        for (const screen of Screens.screens)
            root.applyDesktopLyricsConfig(GlobalConfig.forScreen(screen.name).background.desktopLyrics);

        GlobalConfig.services.lyricsBackend = root.lyricsBackend;
        GlobalConfig.services.lyricsAsyncProviders = root.lyricsAsyncProviders;
        GlobalConfig.services.lyricsNetEaseApiBase = root.lyricsNetEaseApiBase;
        GlobalConfig.services.lyricsDeezerArl = root.lyricsDeezerArl;
        GlobalConfig.services.lyricsSpotifyAccessToken = root.lyricsSpotifyAccessToken;
        GlobalConfig.services.lyricsSpotifyClientId = root.lyricsSpotifyClientId;
        GlobalConfig.services.lyricsSpotifyClientSecret = root.lyricsSpotifyClientSecret;

        GlobalConfig.background.visualiser.enabled = root.visualiserEnabled;
        GlobalConfig.background.visualiser.autoHide = root.visualiserAutoHide;
        GlobalConfig.background.visualiser.rounding = root.visualiserRounding;
        GlobalConfig.background.visualiser.spacing = root.visualiserSpacing;

        if (root.desktopLyricsEnabled)
            LyricsService.loadLyrics();
    }

    anchors.fill: parent

    SplitPaneLayout {
        anchors.fill: parent

        leftContent: Component {
            StyledFlickable {
                id: desktopFlickable

                readonly property var rootPane: root

                flickableDirection: Flickable.VerticalFlick
                contentHeight: desktopLayout.height

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: desktopFlickable
                }

                ColumnLayout {
                    id: desktopLayout

                    readonly property bool allSectionsExpanded: backgroundSection.expanded && desktopLyricsSection.expanded

                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Tokens.spacing.small

                    RowLayout {
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            text: qsTr("Desktop")
                            font.pointSize: Tokens.font.title.large.pointSize
                            font.weight: 500
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        IconButton {
                            icon: desktopLayout.allSectionsExpanded ? "unfold_less" : "unfold_more"
                            type: IconButton.Text
                            label.animate: true
                            onClicked: {
                                const shouldExpand = !desktopLayout.allSectionsExpanded;
                                backgroundSection.expanded = shouldExpand;
                                desktopLyricsSection.expanded = shouldExpand;
                            }
                        }
                    }

                    BackgroundSection {
                        id: backgroundSection

                        expanded: true
                        rootPane: desktopFlickable.rootPane
                    }

                    DesktopLyricsSection {
                        id: desktopLyricsSection

                        rootPane: desktopFlickable.rootPane
                    }
                }
            }
        }

        rightContent: Component {
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: Tokens.spacing.medium
                        text: qsTr("Wallpapers")
                        font.pointSize: Tokens.font.headline.medium.pointSize
                        font.weight: 600
                    }

                    WallpaperGrid {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.bottomMargin: -Tokens.padding.large * 2
                        session: root.session
                    }
                }
            }
        }
    }
}
