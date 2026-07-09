pragma ComponentBehavior: Bound

import ".."
import "../../components"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

CollapsibleSection {
    id: root

    required property var rootPane

    title: qsTr("Desktop Lyrics")
    expanded: true
    showBackground: true

    function saveLyricsProviderConfig(): void {
        rootPane.saveConfig();
        LyricsService.loadLyrics();
    }

    SwitchRow {
        label: qsTr("Enabled")
        checked: rootPane.desktopLyricsEnabled
        onToggled: checked => {
            rootPane.desktopLyricsEnabled = checked;
            rootPane.saveConfig();
        }
    }

    SwitchRow {
        enabled: rootPane.desktopLyricsEnabled
        label: qsTr("Show while paused")
        checked: rootPane.desktopLyricsShowWhilePaused
        onToggled: checked => {
            rootPane.desktopLyricsShowWhilePaused = checked;
            rootPane.saveConfig();
        }
    }

    SectionContainer {
        contentSpacing: Tokens.spacing.medium

        SliderInput {
            Layout.fillWidth: true

            enabled: rootPane.desktopLyricsEnabled
            label: qsTr("Scale")
            value: rootPane.desktopLyricsScale
            from: 0.6
            to: 1.6
            stepSize: 0.05
            decimals: 2
            suffix: "x"
            validator: DoubleValidator {
                bottom: 0.6
                top: 1.6
                decimals: 2
            }

            onValueModified: newValue => {
                rootPane.desktopLyricsScale = newValue;
                rootPane.saveConfig();
            }
        }
    }

    SectionContainer {
        contentSpacing: Tokens.spacing.small

        StyledText {
            text: qsTr("Monitors")
            font.pointSize: Tokens.font.title.medium.pointSize
            font.weight: 500
        }

        Repeater {
            model: rootPane.monitorNames

            SwitchRow {
                required property string modelData

                enabled: rootPane.desktopLyricsEnabled
                label: modelData
                checked: !rootPane.desktopLyricsExcludedScreens.includes(modelData)
                onToggled: checked => rootPane.setDesktopLyricsMonitorEnabled(modelData, checked)
            }
        }
    }

    SectionContainer {
        contentSpacing: Tokens.spacing.small

        StyledText {
            text: qsTr("Sources")
            font.pointSize: Tokens.font.title.medium.pointSize
            font.weight: 500
        }

        SplitButtonRow {
            id: lyricsBackendSelector

            function syncActiveItem(): void {
                switch (rootPane.lyricsBackend) {
                case "Local":
                    active = localItem;
                    break;
                case "LRCLIB":
                    active = lrclibItem;
                    break;
                case "NetEase":
                case "NetEaseV2":
                    active = netEaseItem;
                    break;
                case "Deezer":
                    active = deezerItem;
                    break;
                case "Musixmatch":
                    active = musixmatchItem;
                    break;
                case "SpicyLyrics":
                    active = spicyItem;
                    break;
                default:
                    active = autoItem;
                    break;
                }
            }

            enabled: rootPane.desktopLyricsEnabled
            label: qsTr("Provider")
            menuItems: [autoItem, localItem, lrclibItem, deezerItem, musixmatchItem, spicyItem, netEaseItem]

            Component.onCompleted: syncActiveItem()

            Connections {
                function onLyricsBackendChanged(): void {
                    lyricsBackendSelector.syncActiveItem();
                }

                target: rootPane
            }

            MenuItem {
                id: autoItem

                text: qsTr("Auto")
                icon: "auto_awesome"
                activeText: qsTr("Auto")
                onClicked: {
                    rootPane.lyricsBackend = "Auto";
                    root.saveLyricsProviderConfig();
                }
            }

            MenuItem {
                id: localItem

                text: qsTr("Local")
                icon: "folder"
                activeText: qsTr("Local")
                onClicked: {
                    rootPane.lyricsBackend = "Local";
                    root.saveLyricsProviderConfig();
                }
            }

            MenuItem {
                id: lrclibItem

                text: "LRCLIB"
                icon: "lyrics"
                activeText: "LRCLIB"
                onClicked: {
                    rootPane.lyricsBackend = "LRCLIB";
                    root.saveLyricsProviderConfig();
                }
            }

            MenuItem {
                id: deezerItem

                text: qsTr("Deezer")
                icon: "album"
                activeText: qsTr("Deezer")
                onClicked: {
                    rootPane.lyricsBackend = "Deezer";
                    root.saveLyricsProviderConfig();
                }
            }

            MenuItem {
                id: musixmatchItem

                text: qsTr("Musixmatch")
                icon: "lyrics"
                activeText: qsTr("Musixmatch")
                onClicked: {
                    rootPane.lyricsBackend = "Musixmatch";
                    root.saveLyricsProviderConfig();
                }
            }

            MenuItem {
                id: spicyItem

                text: qsTr("Spicy Lyrics")
                icon: "graphic_eq"
                activeText: qsTr("Spicy Lyrics")
                onClicked: {
                    rootPane.lyricsBackend = "SpicyLyrics";
                    root.saveLyricsProviderConfig();
                }
            }

            MenuItem {
                id: netEaseItem

                text: qsTr("NetEase")
                icon: "cloud"
                activeText: qsTr("NetEase")
                onClicked: {
                    rootPane.lyricsBackend = "NetEase";
                    root.saveLyricsProviderConfig();
                }
            }
        }

        SwitchRow {
            enabled: rootPane.desktopLyricsEnabled
            label: qsTr("Async Auto search")
            checked: rootPane.lyricsAsyncProviders
            onToggled: checked => {
                rootPane.lyricsAsyncProviders = checked;
                root.saveLyricsProviderConfig();
            }
        }

        ProviderTextField {
            enabled: rootPane.desktopLyricsEnabled
            label: qsTr("Deezer ARL")
            password: true
            textValue: rootPane.lyricsDeezerArl
            onAccepted: value => {
                rootPane.lyricsDeezerArl = value.trim();
                root.saveLyricsProviderConfig();
            }
        }

        ProviderTextField {
            enabled: rootPane.desktopLyricsEnabled
            label: qsTr("Spotify access token")
            password: true
            textValue: rootPane.lyricsSpotifyAccessToken
            onAccepted: value => {
                rootPane.lyricsSpotifyAccessToken = value.trim();
                root.saveLyricsProviderConfig();
            }
        }

        ProviderTextField {
            enabled: rootPane.desktopLyricsEnabled
            label: qsTr("Spotify client ID")
            textValue: rootPane.lyricsSpotifyClientId
            onAccepted: value => {
                rootPane.lyricsSpotifyClientId = value.trim();
                root.saveLyricsProviderConfig();
            }
        }

        ProviderTextField {
            enabled: rootPane.desktopLyricsEnabled
            label: qsTr("Spotify client secret")
            password: true
            textValue: rootPane.lyricsSpotifyClientSecret
            onAccepted: value => {
                rootPane.lyricsSpotifyClientSecret = value.trim();
                root.saveLyricsProviderConfig();
            }
        }

        ProviderTextField {
            enabled: rootPane.desktopLyricsEnabled
            label: qsTr("NetEase API base")
            textValue: rootPane.lyricsNetEaseApiBase
            placeholderText: "https://music.xianqiao.wang/neteaseapiv2"
            onAccepted: value => {
                rootPane.lyricsNetEaseApiBase = value.trim();
                root.saveLyricsProviderConfig();
            }
        }
    }

    SectionContainer {
        contentSpacing: Tokens.spacing.small

        StyledText {
            text: qsTr("Background")
            font.pointSize: Tokens.font.title.medium.pointSize
            font.weight: 500
        }

        SwitchRow {
            enabled: rootPane.desktopLyricsEnabled
            label: qsTr("Enabled")
            checked: rootPane.desktopLyricsBackgroundEnabled
            onToggled: checked => {
                rootPane.desktopLyricsBackgroundEnabled = checked;
                rootPane.saveConfig();
            }
        }

        SwitchRow {
            enabled: rootPane.desktopLyricsEnabled
            label: qsTr("Blur enabled")
            checked: rootPane.desktopLyricsBackgroundBlur
            onToggled: checked => {
                rootPane.desktopLyricsBackgroundBlur = checked;
                rootPane.saveConfig();
            }
        }

        SectionContainer {
            contentSpacing: Tokens.spacing.medium

            SliderInput {
                Layout.fillWidth: true

                enabled: rootPane.desktopLyricsEnabled
                label: qsTr("Opacity")
                value: rootPane.desktopLyricsBackgroundOpacity * 100
                from: 0
                to: 100
                suffix: "%"
                validator: IntValidator {
                    bottom: 0
                    top: 100
                }
                formatValueFunction: val => Math.round(val).toString()
                parseValueFunction: text => parseInt(text)

                onValueModified: newValue => {
                    rootPane.desktopLyricsBackgroundOpacity = newValue / 100;
                    rootPane.saveConfig();
                }
            }
        }
    }

    component ProviderTextField: ColumnLayout {
        id: fieldRoot

        required property string label
        property string placeholderText: ""
        property bool password: false
        property string textValue: ""

        signal accepted(string value)

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.fillWidth: true

            text: fieldRoot.label
            color: fieldRoot.enabled ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
            font.pointSize: Tokens.font.label.medium.pointSize
        }

        StyledInputField {
            Layout.fillWidth: true

            enabled: fieldRoot.enabled
            text: fieldRoot.textValue
            placeholderText: fieldRoot.placeholderText
            echoMode: fieldRoot.password ? TextInput.Password : TextInput.Normal
            horizontalAlignment: TextInput.AlignLeft

            onTextEdited: text => fieldRoot.textValue = text
            onEditingFinished: fieldRoot.accepted(text)
        }
    }
}
