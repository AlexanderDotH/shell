pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components.misc
import qs.utils

Singleton {
    id: root

    readonly property list<MprisPlayer> list: Mpris.players.values
    readonly property MprisPlayer active: props.manualActive ?? list.find(p => getIdentity(p) === GlobalConfig.services.defaultPlayer) ?? list[0] ?? null
    readonly property string artCacheDir: `${Paths.imagecache}/media`
    property alias manualActive: props.manualActive
    property string activeArtUrl
    property string pendingArtUrl
    property string downloadingArtUrl
    property string downloadingArtPath

    function syncLyricsTrack(): void {
        const active = root.active;
        if (active && (active.trackArtist || active.trackTitle)) {
            Lyrics.setTrack(active.trackArtist, active.trackTitle, active.trackAlbum, active.length);
        } else {
            Lyrics.clearTrack();
        }
    }

    function normaliseArtUrl(value): string {
        const url = String(value ?? "").trim();
        if (!url)
            return "";
        if (url.startsWith("/") || url.startsWith("~"))
            return encodeURI(`file://${url.replace(/^~/, Quickshell.env("HOME"))}`);
        return encodeURI(url);
    }

    function youtubeVideoId(url): string {
        const match = url.match(/(?:[?&]v=|youtu\.be\/|\/embed\/|\/shorts\/|\/live\/)([A-Za-z0-9_-]{11})/);
        return match?.[1] ?? "";
    }

    function getIdentity(player: MprisPlayer): string {
        if (!player)
            return "";
        const alias = GlobalConfig.services.playerAliases.find(a => a.from === player.identity);
        return alias?.to ?? player.identity;
    }

    function getArtUrl(player: MprisPlayer): string {
        if (!player)
            return "";
        const metadataArt = normaliseArtUrl(player.metadata["mpris:artUrl"]);
        if (metadataArt)
            return metadataArt;

        if (player.trackArtUrl)
            return normaliseArtUrl(player.trackArtUrl);

        const url = player.metadata["xesam:url"] ?? "";
        if (url.includes("youtube.com/") || url.includes("youtu.be/")) {
            const id = youtubeVideoId(url);
            return id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : "";
        }
        return "";
    }

    function isRemoteArtUrl(url: string): bool {
        return /^https?:\/\//i.test(url);
    }

    function hashArtUrl(url: string): string {
        let h1 = 0xdeadbeef, h2 = 0x41c6ce57, ch;
        for (let i = 0; i < url.length; i++) {
            ch = url.charCodeAt(i);
            h1 = Math.imul(h1 ^ ch, 2654435761);
            h2 = Math.imul(h2 ^ ch, 1597334677);
        }
        h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507);
        h1 ^= Math.imul(h2 ^ (h2 >>> 13), 3266489909);
        h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507);
        h2 ^= Math.imul(h1 ^ (h1 >>> 13), 3266489909);
        return (h2 >>> 0).toString(16).padStart(8, "0") + (h1 >>> 0).toString(16).padStart(8, "0");
    }

    function cachedArtPath(url: string): string {
        return `${artCacheDir}/${hashArtUrl(url)}.jpg`;
    }

    function updateActiveArtUrl(): void {
        const artUrl = getArtUrl(active);
        if (!artUrl) {
            pendingArtUrl = "";
            activeArtUrl = "";
            return;
        }

        if (!isRemoteArtUrl(artUrl)) {
            pendingArtUrl = "";
            activeArtUrl = artUrl;
            return;
        }

        pendingArtUrl = artUrl;
        if (downloadingArtUrl === artUrl && artDownloadProc.running)
            return;

        const cacheUrl = normaliseArtUrl(cachedArtPath(artUrl));
        if (activeArtUrl === cacheUrl)
            return;

        startArtDownload();
    }

    function startArtDownload(): void {
        if (!pendingArtUrl || artDownloadProc.running)
            return;

        downloadingArtUrl = pendingArtUrl;
        downloadingArtPath = cachedArtPath(downloadingArtUrl);
        artDownloadProc.command = ["sh", "-c", "mkdir -p \"$1\" && { [ -s \"$2\" ] || { tmp=\"$2.tmp.$$\"; curl -fsSL --globoff --max-time 20 --retry 1 --user-agent \"caelestia-shell\" -o \"$tmp\" \"$3\" && mv \"$tmp\" \"$2\"; }; }", "caelestia-art", artCacheDir, downloadingArtPath, downloadingArtUrl];
        artDownloadProc.running = true;
    }

    function finishArtDownload(exitCode: int): void {
        const completedUrl = downloadingArtUrl;
        const completedPath = downloadingArtPath;
        downloadingArtUrl = "";
        downloadingArtPath = "";

        if (exitCode === 0 && completedUrl === pendingArtUrl) {
            activeArtUrl = normaliseArtUrl(completedPath);
        } else if (exitCode !== 0 && completedUrl === pendingArtUrl) {
            activeArtUrl = completedUrl;
        }

        if (pendingArtUrl && pendingArtUrl !== completedUrl)
            Qt.callLater(startArtDownload);
    }

    Connections {
        function onPostTrackChanged() {
            root.syncLyricsTrack();
            root.updateActiveArtUrl();

            if (!GlobalConfig.utilities.toasts.nowPlaying) {
                return;
            }
            if (root.active.trackArtist != "" && root.active.trackTitle != "") {
                Toaster.toast(qsTr("Now Playing"), qsTr("%1 - %2").arg(root.active.trackArtist).arg(root.active.trackTitle), "music_note");
            }
        }

        function onMetadataChanged() {
            root.updateActiveArtUrl();
        }

        function onTrackArtUrlChanged() {
            root.updateActiveArtUrl();
        }

        ignoreUnknownSignals: true
        target: root.active
    }

    onActiveChanged: Qt.callLater(() => {
        syncLyricsTrack();
        updateActiveArtUrl();
    })

    Component.onCompleted: Qt.callLater(() => {
        syncLyricsTrack();
        updateActiveArtUrl();
    })

    PersistentProperties {
        id: props

        property MprisPlayer manualActive

        reloadableId: "players"
    }

    Process {
        id: artDownloadProc

        onExited: code => root.finishArtDownload(code) // qmllint disable signal-handler-parameters
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaToggle"
        description: "Toggle media playback"
        onPressed: {
            const active = root.active;
            if (active && active.canTogglePlaying)
                active.togglePlaying();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaPrev"
        description: "Previous track"
        onPressed: {
            const active = root.active;
            if (active && active.canGoPrevious)
                active.previous();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaNext"
        description: "Next track"
        onPressed: {
            const active = root.active;
            if (active && active.canGoNext)
                active.next();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaStop"
        description: "Stop media playback"
        onPressed: root.active?.stop()
    }

    IpcHandler {
        function getActive(prop: string): string {
            const active = root.active;
            return active ? active[prop] ?? "Invalid property" : "No active player";
        }

        function list(): string {
            return root.list.map(p => root.getIdentity(p)).join("\n");
        }

        function play(): void {
            const active = root.active;
            if (active?.canPlay)
                active.play();
        }

        function pause(): void {
            const active = root.active;
            if (active?.canPause)
                active.pause();
        }

        function playPause(): void {
            const active = root.active;
            if (active?.canTogglePlaying)
                active.togglePlaying();
        }

        function previous(): void {
            const active = root.active;
            if (active?.canGoPrevious)
                active.previous();
        }

        function next(): void {
            const active = root.active;
            if (active?.canGoNext)
                active.next();
        }

        function stop(): void {
            root.active?.stop();
        }

        target: "mpris"
    }
}
