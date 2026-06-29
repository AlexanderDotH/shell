pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components.misc

Singleton {
    id: root

    readonly property list<MprisPlayer> list: Mpris.players.values
    readonly property MprisPlayer active: props.manualActive ?? list.find(p => getIdentity(p) === GlobalConfig.services.defaultPlayer) ?? list[0] ?? null
    property string activeArtUrl: ""
    property alias manualActive: props.manualActive

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
        if (player.trackArtUrl)
            return normaliseArtUrl(player.trackArtUrl);

        const metadataArt = normaliseArtUrl(player.metadata["mpris:artUrl"]);
        if (metadataArt)
            return metadataArt;

        const url = player.metadata["xesam:url"] ?? "";
        if (url.includes("youtube.com/") || url.includes("youtu.be/")) {
            const id = youtubeVideoId(url);
            return id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : "";
        }
        return "";
    }

    function syncActiveArtUrl(): void {
        activeArtUrl = getArtUrl(active);
    }

    Connections {
        function onPostTrackChanged() {
            root.syncLyricsTrack();
            root.syncActiveArtUrl();

            if (!GlobalConfig.utilities.toasts.nowPlaying) {
                return;
            }
            if (root.active.trackArtist != "" && root.active.trackTitle != "") {
                Toaster.toast(qsTr("Now Playing"), qsTr("%1 - %2").arg(root.active.trackArtist).arg(root.active.trackTitle), "music_note");
            }
        }

        function onMetadataChanged() {
            root.syncActiveArtUrl();
        }

        function onTrackArtUrlChanged() {
            root.syncActiveArtUrl();
        }

        ignoreUnknownSignals: true

        target: root.active
    }

    onActiveChanged: {
        Qt.callLater(syncLyricsTrack);
        Qt.callLater(syncActiveArtUrl);
    }

    Component.onCompleted: {
        Qt.callLater(syncLyricsTrack);
        Qt.callLater(syncActiveArtUrl);
    }

    PersistentProperties {
        id: props

        property MprisPlayer manualActive

        reloadableId: "players"
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
