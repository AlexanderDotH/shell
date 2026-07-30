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

    readonly property MprisPlayer active: props.manualActive ?? list.find(p => getIdentity(p) === GlobalConfig.services.defaultPlayer) ?? list[0] ?? null
    property string activeArtUrl
    readonly property string artCacheDir: `${Paths.imagecache}/media`
    property string downloadingArtPath
    property string downloadingArtUrl

    // Dedup key for progressive metadata (e.g. mpv-mpris/yt-dlp player fills title then artist later).
    property string lastNowPlayingKey: ""
    readonly property list<MprisPlayer> list: Mpris.players.values
    property alias manualActive: props.manualActive
    property string pendingArtUrl

    function cachedArtPath(url: string): string {
        return `${artCacheDir}/${hashArtUrl(url)}.jpg`;
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

    function getIdentity(player: MprisPlayer): string {
        if (!player)
            return "";
        const alias = GlobalConfig.services.playerAliases.find(a => a.from === player.identity);
        return alias?.to ?? player.identity;
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

    function isRemoteArtUrl(url: string): bool {
        return /^https?:\/\//i.test(url);
    }

    // Quickshell only emits postTrackChanged when trackid/url/title change, so late
    // artist updates (common with mpv-mpris + yt-dlp player) never retrigger it. Watch
    // title/artist too and toast once both are usable.
    function maybeToastNowPlaying(): void {
        if (!GlobalConfig.utilities.toasts.nowPlaying)
            return;

        const player = root.active;
        if (!player)
            return;

        const title = player.trackTitle ?? "";
        const artist = player.trackArtist ?? "";
        if (!title || !artist)
            return;

        const key = `${getIdentity(player)}\0${player.uniqueId}\0${title}\0${artist}`;
        if (key === lastNowPlayingKey)
            return;

        lastNowPlayingKey = key;
        Toaster.toast(qsTr("Now Playing"), qsTr("%1 - %2").arg(artist).arg(title), "music_note");
    }

    function normaliseArtUrl(value): string {
        const url = String(value ?? "").trim();
        if (!url)
            return "";
        if (url.startsWith("/") || url.startsWith("~"))
            return encodeURI(`file://${url.replace(/^~/, Quickshell.env("HOME"))}`);
        return encodeURI(url);
    }

    function startArtDownload(): void {
        if (!pendingArtUrl || artDownloadProc.running)
            return;

        downloadingArtUrl = pendingArtUrl;
        downloadingArtPath = cachedArtPath(downloadingArtUrl);
        artDownloadProc.command = ["sh", "-c", "mkdir -p \"$1\" && { [ -s \"$2\" ] || { tmp=\"$2.tmp.$$\"; curl -fsSL --globoff --max-time 20 --retry 1 --user-agent \"caelestia-shell\" -o \"$tmp\" \"$3\" && mv \"$tmp\" \"$2\"; }; }", "caelestia-art", artCacheDir, downloadingArtPath, downloadingArtUrl];
        artDownloadProc.running = true;
    }

    function syncLyricsTrack(): void {
        const active = root.active;
        if (active && (active.trackArtist || active.trackTitle)) {
            Lyrics.setTrack(active.trackArtist, active.trackTitle, active.trackAlbum, active.length);
        } else {
            Lyrics.clearTrack();
        }
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

    function youtubeVideoId(url): string {
        const match = url.match(/(?:[?&]v=|youtu\.be\/|\/embed\/|\/shorts\/|\/live\/)([A-Za-z0-9_-]{11})/);
        return match?.[1] ?? "";
    }

    Component.onCompleted: {
        Qt.callLater(syncLyricsTrack);
        Qt.callLater(updateActiveArtUrl);
    }
    onActiveChanged: {
        lastNowPlayingKey = "";
        Qt.callLater(syncLyricsTrack);
        Qt.callLater(updateActiveArtUrl);
    }

    Connections {
        function onLengthChanged(): void {
            root.syncLyricsTrack();
        }

        function onMetadataChanged(): void {
            root.updateActiveArtUrl();
        }

        function onPostTrackChanged(): void {
            root.syncLyricsTrack();
            root.updateActiveArtUrl();
            root.maybeToastNowPlaying();
        }

        function onTrackAlbumChanged(): void {
            root.syncLyricsTrack();
        }

        function onTrackArtUrlChanged(): void {
            root.updateActiveArtUrl();
        }

        function onTrackArtistChanged(): void {
            root.syncLyricsTrack();
            root.maybeToastNowPlaying();
        }

        function onTrackTitleChanged(): void {
            root.syncLyricsTrack();
            root.maybeToastNowPlaying();
        }

        ignoreUnknownSignals: true
        target: root.active
    }

    PersistentProperties {
        id: props

        property MprisPlayer manualActive

        reloadableId: "players"
    }

    Process {
        id: artDownloadProc

        // qmllint disable signal-handler-parameters
        onExited: code => root.finishArtDownload(code)
        // qmllint enable signal-handler-parameters
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        description: "Toggle media playback"
        // qmllint enable unresolved-type
        name: "mediaToggle"

        onPressed: {
            const active = root.active;
            if (active && active.canTogglePlaying)
                active.togglePlaying();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        description: "Previous track"
        // qmllint enable unresolved-type
        name: "mediaPrev"

        onPressed: {
            const active = root.active;
            if (active && active.canGoPrevious)
                active.previous();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        description: "Next track"
        // qmllint enable unresolved-type
        name: "mediaNext"

        onPressed: {
            const active = root.active;
            if (active && active.canGoNext)
                active.next();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        description: "Stop media playback"
        // qmllint enable unresolved-type
        name: "mediaStop"

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

        function next(): void {
            const active = root.active;
            if (active?.canGoNext)
                active.next();
        }

        function pause(): void {
            const active = root.active;
            if (active?.canPause)
                active.pause();
        }

        function play(): void {
            const active = root.active;
            if (active?.canPlay)
                active.play();
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

        function stop(): void {
            root.active?.stop();
        }

        target: "mpris"
    }
}
