pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.Services
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Lyrics")
    isSubPage: true

    // Online fallback order in Auto: LRCLIB -> Deezer -> Musixmatch -> Spicy Lyrics -> NetEase
    readonly property list<MenuItem> lyricsBackendItems: [
        MenuItem {
            text: qsTr("Auto")
            icon: "auto_awesome"
            value: LyricsBackend.Auto
        },
        MenuItem {
            text: qsTr("Local")
            icon: "folder"
            value: LyricsBackend.Local
        },
        MenuItem {
            text: "LRCLIB"
            icon: "lyrics"
            value: LyricsBackend.LRCLIB
        },
        MenuItem {
            text: "Deezer"
            icon: "album"
            value: LyricsBackend.Deezer
        },
        MenuItem {
            text: "Musixmatch"
            icon: "lyrics"
            value: LyricsBackend.Musixmatch
        },
        MenuItem {
            text: "Spicy Lyrics"
            icon: "graphic_eq"
            value: LyricsBackend.SpicyLyrics
        },
        MenuItem {
            text: "NetEase"
            icon: "cloud"
            value: LyricsBackend.NetEase
        }
    ]

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

    function setLyricsBackend(backend: int): void {
        if (backend < 0)
            return;

        Lyrics.preferredBackend = backend;
        Lyrics.refresh();
    }

    function activeLyricsBackendItem(): MenuItem {
        for (const item of lyricsBackendItems) {
            if (item.value === Lyrics.preferredBackend)
                return item;
        }
        return lyricsBackendItems[0];
    }

    function normalizedValue(value: real, from: real, to: real): real {
        return Math.max(0, Math.min((value - from) / (to - from), 1));
    }

    function lyricsBackendStatus(): string {
        if (Lyrics.loading)
            return qsTr("Loading via %1").arg(LyricsBackend.toString(Lyrics.backend));
        if (Lyrics.hasLyrics)
            return qsTr("Using %1").arg(LyricsBackend.toString(Lyrics.backend));
        return qsTr("Provider: %1").arg(LyricsBackend.toString(Lyrics.preferredBackend));
    }

    function lyricsTrackStatus(): string {
        if (!Players.active)
            return qsTr("No active player");
        if (Lyrics.trackArtist || Lyrics.trackTitle)
            return qsTr("%1 - %2").arg(Lyrics.trackArtist || qsTr("Unknown artist")).arg(Lyrics.trackTitle || qsTr("Unknown title"));
        return qsTr("Waiting for track metadata");
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

    function activeLyricsCandidateItem(items: var): var {
        for (const item of items) {
            if (lyricsCandidateMatches(item.value, Lyrics.selectedCandidate))
                return item;
        }
        return null;
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

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Variants {
            id: lyricsCandidateVariants

            model: Lyrics.lyricCandidates

            MenuItem {
                required property var modelData

                text: root.lyricsCandidateLabel(modelData)
                icon: root.lyricsCandidateMatches(modelData, Lyrics.selectedCandidate) ? "check" : root.lyricsBackendIcon(modelData.backend)
                activeIcon: root.lyricsBackendIcon(modelData.backend)
                activeText: LyricsBackend.toString(modelData.backend)
                value: modelData
            }
        }

        SectionHeader {
            first: true
            text: qsTr("Lyrics source")
        }

        SelectRow {
            first: true
            label: qsTr("Provider")
            subtext: root.lyricsBackendStatus()
            menuItems: root.lyricsBackendItems
            active: root.activeLyricsBackendItem()
            onSelected: item => root.setLyricsBackend(item.value)
        }

        SelectRow {
            label: qsTr("Match")
            subtext: root.lyricsCandidateStatus(lyricsCandidateVariants.instances)
            menuItems: lyricsCandidateVariants.instances
            active: root.activeLyricsCandidateItem(lyricsCandidateVariants.instances)
            fallbackIcon: Lyrics.loading ? "hourglass_top" : "lyrics"
            fallbackText: Lyrics.loading ? qsTr("Loading") : qsTr("Auto")
            enabled: lyricsCandidateVariants.instances.length > 0
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
            placeholder: "~/Music/Lyrics"
            leadingIcon: "folder"
            text: GlobalConfig.paths.lyricsDir
            onCommitted: value => {
                GlobalConfig.paths.lyricsDir = value;
                Lyrics.refresh();
            }
        }

        NavRow {
            last: true
            icon: "refresh"
            label: qsTr("Refresh lyrics")
            status: root.lyricsBackendStatus()
            onClicked: Lyrics.refresh()
        }

        SectionHeader {
            text: qsTr("Provider settings")
        }

        LyricsTextField {
            first: true
            label: qsTr("NetEase API base")
            placeholder: "https://music.xianqiao.wang/neteaseapiv2"
            leadingIcon: "cloud"
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
            first: true
            text: qsTr("Show desktop lyrics")
            subtext: Lyrics.hasLyrics ? root.lyricsTrackStatus() : qsTr("Synced lyrics over the wallpaper")
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
                onToggled: root.setDesktopLyricsMonitorEnabled(modelData.name, checked)
            }
        }
    }

    component LyricsTextField: M3TextField {
        id: fieldRoot

        property bool trimValue: true
        property bool first: false

        signal committed(string value)

        Layout.fillWidth: true
        Layout.topMargin: first ? 0 : Tokens.spacing.extraSmall
        inputMethodHints: Qt.ImhNoPredictiveText

        function commit(): void {
            const value = trimValue ? text.trim() : text;
            fieldRoot.committed(value);
        }

        onAccepted: commit()

        Connections {
            target: fieldRoot.field
            function onEditingFinished(): void {
                fieldRoot.commit();
            }
        }
    }
}
