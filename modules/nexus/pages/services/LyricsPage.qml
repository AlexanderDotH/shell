pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.Services
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import qs.modules.nexus.pages.services

PageBase {
    id: root

    // Online fallback order in Auto: LRCLIB -> Deezer -> Musixmatch -> Spicy Lyrics -> NetEase
    readonly property list<MenuItem> lyricsBackendItems: [
        MenuItem {
            icon: "auto_awesome"
            text: qsTr("Auto")
            value: LyricsBackend.Auto
        },
        MenuItem {
            icon: "folder"
            text: qsTr("Local")
            value: LyricsBackend.Local
        },
        MenuItem {
            icon: "lyrics"
            text: "LRCLIB"
            value: LyricsBackend.LRCLIB
        },
        MenuItem {
            icon: "album"
            text: "Deezer"
            value: LyricsBackend.Deezer
        },
        MenuItem {
            icon: "lyrics"
            text: "Musixmatch"
            value: LyricsBackend.Musixmatch
        },
        MenuItem {
            icon: "graphic_eq"
            text: "Spicy Lyrics"
            value: LyricsBackend.SpicyLyrics
        },
        MenuItem {
            icon: "cloud"
            text: "NetEase"
            value: LyricsBackend.NetEase
        }
    ]

    function activeLyricsCandidateItem(items: var): var {
        for (const item of items) {
            if (lyricsCandidateMatches(item.value, Lyrics.selectedCandidate))
                return item;
        }
        return null;
    }

    function forEachDesktopLyricsConfig(callback: var): void {
        callback(GlobalConfig.background.desktopLyrics);
        for (const screen of Screens.screens)
            callback(GlobalConfig.forScreen(screen.name).background.desktopLyrics);
    }

    function lyricsBackendIcon(backend: int): string {
        switch (backend) {
        case LyricsBackend.Local:
            return "folder";
        case LyricsBackend.LRCLIB:
            return "lyrics";
        case LyricsBackend.NetEase:
            return "cloud";
        case LyricsBackend.Deezer:
            return "album";
        case LyricsBackend.Musixmatch:
            return "lyrics";
        case LyricsBackend.SpicyLyrics:
            return "graphic_eq";
        case LyricsBackend.Auto:
        default:
            return "auto_awesome";
        }
    }

    function lyricsBackendStatus(): string {
        if (Lyrics.loading)
            return qsTr("Loading via %1").arg(LyricsBackend.toString(Lyrics.backend));
        if (Lyrics.hasLyrics)
            return qsTr("Using %1").arg(LyricsBackend.toString(Lyrics.backend));
        return qsTr("Provider: %1").arg(LyricsBackend.toString(Lyrics.preferredBackend));
    }

    function lyricsCandidateLabel(candidate: var): string {
        if (!candidate)
            return qsTr("No match");

        const backend = LyricsBackend.toString(candidate.backend);
        const artist = candidate.artist || Lyrics.trackArtist || qsTr("Unknown artist");
        const title = candidate.title || Lyrics.trackTitle || qsTr("Unknown title");
        return qsTr("%1: %2 - %3").arg(backend).arg(artist).arg(title);
    }

    function lyricsCandidateMatches(a: var, b: var): bool {
        return !!a && !!b && a.backend === b.backend && a.id === b.id;
    }

    function lyricsCandidateStatus(candidateItems: var): string {
        if (Lyrics.loading)
            return qsTr("Searching matches");
        if (Lyrics.selectedCandidate.id)
            return lyricsCandidateLabel(Lyrics.selectedCandidate);
        if (candidateItems.length > 0)
            return qsTr("%1 matches available").arg(candidateItems.length);
        return qsTr("No matches available");
    }

    function lyricsTrackStatus(): string {
        if (!Players.active)
            return qsTr("No active player");
        if (Lyrics.trackArtist || Lyrics.trackTitle)
            return qsTr("%1 - %2").arg(Lyrics.trackArtist || qsTr("Unknown artist")).arg(Lyrics.trackTitle || qsTr("Unknown title"));
        return qsTr("Waiting for track metadata");
    }

    function normalizedValue(value: real, from: real, to: real): real {
        return Math.max(0, Math.min((value - from) / (to - from), 1));
    }

    function setDesktopLyricsBackgroundBlur(blur: bool): void {
        forEachDesktopLyricsConfig(config => {
            config.background.blur = blur;
        });
    }

    function setDesktopLyricsBackgroundEnabled(enabled: bool): void {
        forEachDesktopLyricsConfig(config => {
            config.background.enabled = enabled;
        });
    }

    function setDesktopLyricsBackgroundOpacity(opacity: real): void {
        forEachDesktopLyricsConfig(config => {
            config.background.opacity = opacity;
        });
    }

    function setDesktopLyricsEnabled(enabled: bool): void {
        forEachDesktopLyricsConfig(config => {
            config.enabled = enabled;
        });
        if (enabled)
            Lyrics.refresh();
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

    function setLyricsBackend(backend: int): void {
        if (backend < 0)
            return;

        Lyrics.preferredBackend = backend;
        Lyrics.refresh();
    }

    isSubPage: true
    title: qsTr("Lyrics")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        spacing: Tokens.spacing.extraSmall / 2
        width: root.cappedWidth

        Variants {
            id: lyricsCandidateVariants

            model: Lyrics.lyricCandidates

            MenuItem {
                required property var modelData

                activeIcon: root.lyricsBackendIcon(modelData.backend)
                activeText: LyricsBackend.toString(modelData.backend)
                icon: root.lyricsCandidateMatches(modelData, Lyrics.selectedCandidate) ? "check" : root.lyricsBackendIcon(modelData.backend)
                text: root.lyricsCandidateLabel(modelData)
                value: modelData
            }
        }

        SectionHeader {
            first: true
            text: qsTr("Lyrics source")
        }

        SelectRow {
            active: root.lyricsBackendItems.find(item => item.value === Lyrics.preferredBackend) ?? root.lyricsBackendItems[0]
            first: true
            label: qsTr("Provider")
            menuItems: root.lyricsBackendItems
            subtext: root.lyricsBackendStatus()

            onSelected: item => root.setLyricsBackend(item.value)
        }

        ToggleRow {
            checked: GlobalConfig.services.lyricsAsyncProviders
            subtext: qsTr("Wait for every online provider, then keep the first in order")
            text: qsTr("Async Auto search")

            onToggled: {
                GlobalConfig.services.lyricsAsyncProviders = checked;
                Lyrics.refresh();
            }
        }

        SelectRow {
            active: root.activeLyricsCandidateItem(lyricsCandidateVariants.instances)
            enabled: lyricsCandidateVariants.instances.length > 0
            fallbackIcon: Lyrics.loading ? "hourglass_top" : "lyrics"
            fallbackText: Lyrics.loading ? qsTr("Loading") : qsTr("Auto")
            label: qsTr("Match")
            menuItems: lyricsCandidateVariants.instances
            subtext: root.lyricsCandidateStatus(lyricsCandidateVariants.instances)

            onSelected: item => {
                Lyrics.selectedCandidate = item.value;
            }
        }

        InfoRow {
            icon: "album"
            label: qsTr("Current track")
            subtext: root.lyricsTrackStatus()
            value: Lyrics.hasLyrics ? qsTr("%1 lines").arg(Lyrics.lyrics.length) : ""
        }

        LyricsTextField {
            label: qsTr("Local folder")
            leadingIcon: "folder"
            placeholder: "~/Music/Lyrics"
            text: GlobalConfig.paths.lyricsDir

            onCommitted: value => {
                GlobalConfig.paths.lyricsDir = value;
                Lyrics.refresh();
            }
        }

        NavRow {
            icon: "refresh"
            label: qsTr("Refresh lyrics")
            last: true
            status: root.lyricsBackendStatus()

            onClicked: Lyrics.refresh()
        }

        SectionHeader {
            text: qsTr("Provider settings")
        }

        LyricsTextField {
            first: true
            label: qsTr("NetEase API base")
            leadingIcon: "cloud"
            placeholder: "https://music.xianqiao.wang/neteaseapiv2"
            text: GlobalConfig.services.lyricsNetEaseApiBase

            onCommitted: value => {
                GlobalConfig.services.lyricsNetEaseApiBase = value;
                Lyrics.refresh();
            }
        }

        LyricsTextField {
            label: qsTr("Deezer ARL")
            leadingIcon: "album"
            password: true
            text: GlobalConfig.services.lyricsDeezerArl

            onCommitted: value => {
                GlobalConfig.services.lyricsDeezerArl = value;
                Lyrics.refresh();
            }
        }

        LyricsTextField {
            label: qsTr("Spotify access token")
            leadingIcon: "key"
            password: true
            text: GlobalConfig.services.lyricsSpotifyAccessToken

            onCommitted: value => {
                GlobalConfig.services.lyricsSpotifyAccessToken = value;
                Lyrics.refresh();
            }
        }

        LyricsTextField {
            label: qsTr("Spotify client ID")
            leadingIcon: "badge"
            text: GlobalConfig.services.lyricsSpotifyClientId

            onCommitted: value => {
                GlobalConfig.services.lyricsSpotifyClientId = value;
                Lyrics.refresh();
            }
        }

        LyricsTextField {
            label: qsTr("Spotify client secret")
            leadingIcon: "vpn_key"
            password: true
            text: GlobalConfig.services.lyricsSpotifyClientSecret

            onCommitted: value => {
                GlobalConfig.services.lyricsSpotifyClientSecret = value;
                Lyrics.refresh();
            }
        }

        SectionHeader {
            text: qsTr("Desktop lyrics")
        }

        ToggleRow {
            checked: GlobalConfig.background.desktopLyrics.enabled
            first: true
            subtext: Lyrics.hasLyrics ? root.lyricsTrackStatus() : qsTr("Synced lyrics over the wallpaper")
            text: qsTr("Show desktop lyrics")

            onToggled: root.setDesktopLyricsEnabled(checked)
        }

        ToggleRow {
            checked: GlobalConfig.background.desktopLyrics.showWhilePaused
            enabled: GlobalConfig.background.desktopLyrics.enabled
            text: qsTr("Show while paused")

            onToggled: root.setDesktopLyricsShowWhilePaused(checked)
        }

        SliderRow {
            enabled: GlobalConfig.background.desktopLyrics.enabled
            icon: "format_size"
            label: qsTr("Text scale")
            value: root.normalizedValue(GlobalConfig.background.desktopLyrics.scale, 0.6, 2)
            valueLabel: `${Math.round(GlobalConfig.background.desktopLyrics.scale * 100)}%`

            onMoved: v => root.setDesktopLyricsScale(Math.round((0.6 + v * 1.4) * 100) / 100)
        }

        ToggleRow {
            checked: GlobalConfig.background.desktopLyrics.background.enabled
            enabled: GlobalConfig.background.desktopLyrics.enabled
            text: qsTr("Background plate")

            onToggled: root.setDesktopLyricsBackgroundEnabled(checked)
        }

        ToggleRow {
            checked: GlobalConfig.background.desktopLyrics.background.blur
            enabled: GlobalConfig.background.desktopLyrics.enabled && GlobalConfig.background.desktopLyrics.background.enabled
            text: qsTr("Blur behind lyrics")

            onToggled: root.setDesktopLyricsBackgroundBlur(checked)
        }

        SliderRow {
            enabled: GlobalConfig.background.desktopLyrics.enabled && GlobalConfig.background.desktopLyrics.background.enabled
            icon: "opacity"
            label: qsTr("Plate opacity")
            last: Screens.screens.length === 0
            value: GlobalConfig.background.desktopLyrics.background.opacity
            valueLabel: `${Math.round(GlobalConfig.background.desktopLyrics.background.opacity * 100)}%`

            onMoved: v => root.setDesktopLyricsBackgroundOpacity(Math.round(v * 100) / 100)
        }

        Repeater {
            model: Screens.screens

            ToggleRow {
                required property int index
                required property var modelData

                checked: !(GlobalConfig.background.desktopLyrics.excludedScreens ?? []).includes(modelData.name)
                enabled: GlobalConfig.background.desktopLyrics.enabled
                last: index === Screens.screens.length - 1
                text: qsTr("Show on %1").arg(modelData.name)

                onToggled: root.setDesktopLyricsMonitorEnabled(modelData.name, checked)
            }
        }
    }
}
