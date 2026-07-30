pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    readonly property string activeSpecial: (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? monitor : Hypr.focusedMonitor)?.lastIpcObject.specialWorkspace?.name ?? ""
    readonly property var monitor: Hypr.safeMonitorFor(screen)
    required property ShellScreen screen

    layer.enabled: true
    visible: monitor !== null

    layer.effect: Mask {
        maskSource: mask
    }

    Item {
        id: mask

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: Tokens.rounding.full

            gradient: Gradient {
                orientation: Gradient.Vertical

                GradientStop {
                    color: Qt.rgba(0, 0, 0, 0)
                    position: 0
                }

                GradientStop {
                    color: Qt.rgba(0, 0, 0, 1)
                    position: 0.3
                }

                GradientStop {
                    color: Qt.rgba(0, 0, 0, 1)
                    position: 0.7
                }

                GradientStop {
                    color: Qt.rgba(0, 0, 0, 0)
                    position: 1
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            implicitHeight: parent.height / 2
            opacity: view.contentY > 0 ? 0 : 1
            radius: Tokens.rounding.full

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: parent.height / 2
            opacity: view.contentY < view.contentHeight - parent.height + Tokens.padding.extraSmall ? 0 : 1
            radius: Tokens.rounding.full

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    ListView {
        id: view

        anchors.fill: parent
        currentIndex: model.values.findIndex(w => w.name === root.activeSpecial)
        highlightFollowsCurrentItem: false
        highlightRangeMode: ListView.StrictlyEnforceRange
        interactive: false
        preferredHighlightBegin: 0
        preferredHighlightEnd: height
        spacing: Tokens.spacing.medium

        add: Transition {
            Anim {
                easing: Tokens.anim.standardDecel
                from: 0
                properties: "scale"
                to: 1
            }
        }
        delegate: SpecialWsDelegate {}
        displaced: Transition {
            Anim {
                easing: Tokens.anim.standardDecel
                properties: "scale"
                to: 1
            }

            Anim {
                properties: "x,y"
            }
        }
        highlight: Item {
            implicitHeight: (view.currentItem as SpecialWsDelegate)?.size ?? 0
            y: view.currentItem?.y ?? 0

            Behavior on y {
                Anim {}
            }
        }
        model: ScriptModel {
            values: Hypr.workspaces.values.filter(w => w.name.startsWith("special:") && (!GlobalConfig.bar.workspaces.perMonitorWorkspaces || (root.monitor && w.monitor === root.monitor)))
        }
        move: Transition {
            Anim {
                easing: Tokens.anim.standardDecel
                properties: "scale"
                to: 1
            }

            Anim {
                properties: "x,y"
            }
        }
        remove: Transition {
            Anim {
                property: "scale"
                to: 0.5
                type: Anim.StandardSmall
            }

            Anim {
                property: "opacity"
                to: 0
                type: Anim.StandardSmall
            }
        }

        onCurrentIndexChanged: currentIndex = Qt.binding(() => model.values.findIndex(w => w.name === root.activeSpecial))
    }

    Loader {
        active: Config.bar.workspaces.activeIndicator
        anchors.fill: parent
        asynchronous: true

        sourceComponent: Item {
            StyledClippingRect {
                id: indicator

                anchors.left: parent.left
                anchors.right: parent.right
                color: Colours.palette.m3tertiary
                implicitHeight: (view.currentItem as SpecialWsDelegate)?.size ?? 0
                radius: Tokens.rounding.full
                y: (view.currentItem?.y ?? 0) - view.contentY

                Behavior on implicitHeight {
                    Anim {
                        type: Anim.Emphasized
                    }
                }
                Behavior on y {
                    Anim {
                        type: Anim.Emphasized
                    }
                }

                Colouriser {
                    anchors.horizontalCenter: parent.horizontalCenter
                    colorizationColor: Colours.palette.m3onTertiary
                    implicitHeight: view.height
                    implicitWidth: view.width
                    source: view
                    sourceColor: Colours.palette.m3onSurface
                    x: 0
                    y: -indicator.y
                }
            }
        }
    }

    MouseArea {
        property real startY

        anchors.fill: view
        drag.axis: Drag.YAxis
        drag.maximumY: 0
        drag.minimumY: Math.min(0, view.height - view.contentHeight - Tokens.padding.extraSmall)
        drag.target: view.contentItem

        onClicked: event => {
            if (Math.abs(event.y - startY) > drag.threshold)
                return;

            const ws = view.itemAt(event.x, event.y) as SpecialWsDelegate;
            if (ws?.modelData)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.workspace.toggle_special("${ws.modelData.name.slice(8)}")` : `togglespecialworkspace ${ws.modelData.name.slice(8)}`);
            else
                Hypr.dispatch(Hypr.usingLua ? 'hl.dsp.workspace.toggle_special("special")' : "togglespecialworkspace special");
        }
        onPressed: event => startY = event.y
    }

    component SpecialWsDelegate: ColumnLayout {
        id: ws

        property bool hasWindows
        property string icon
        required property HyprlandWorkspace modelData
        readonly property int size: label.Layout.preferredHeight + (hasWindows ? windows.implicitHeight + Tokens.padding.extraSmall : 0)
        property int wsId

        anchors.left: view.contentItem.left
        anchors.right: view.contentItem.right
        spacing: 0

        Component.onCompleted: {
            wsId = modelData.id;
            icon = Icons.getSpecialWsIcon(modelData.name);
            hasWindows = Config.bar.workspaces.showWindowsOnSpecialWorkspaces && modelData.lastIpcObject.windows > 0;
        }

        // Hacky thing cause modelData gets destroyed before the remove anim finishes
        Connections {
            function onIdChanged(): void {
                if (ws.modelData)
                    ws.wsId = ws.modelData.id;
            }

            function onLastIpcObjectChanged(): void {
                if (ws.modelData)
                    ws.hasWindows = root.Config.bar.workspaces.showWindowsOnSpecialWorkspaces && ws.modelData.lastIpcObject.windows > 0;
            }

            function onNameChanged(): void {
                if (ws.modelData)
                    ws.icon = Icons.getSpecialWsIcon(ws.modelData.name);
            }

            target: ws.modelData
        }

        Connections {
            function onShowWindowsOnSpecialWorkspacesChanged(): void {
                if (ws.modelData)
                    ws.hasWindows = root.Config.bar.workspaces.showWindowsOnSpecialWorkspaces && ws.modelData.lastIpcObject.windows > 0;
            }

            target: root.Config.bar.workspaces
        }

        Loader {
            id: label

            Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
            Layout.preferredHeight: Tokens.sizes.bar.innerWidth - Tokens.padding.small
            asynchronous: true
            sourceComponent: ws.icon.length === 1 ? letterComp : iconComp

            Component {
                id: iconComp

                MaterialIcon {
                    fill: 1
                    text: ws.icon
                    verticalAlignment: Qt.AlignVCenter
                }
            }

            Component {
                id: letterComp

                StyledText {
                    text: ws.icon
                    verticalAlignment: Qt.AlignVCenter
                }
            }
        }

        Loader {
            id: windows

            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            Layout.preferredHeight: implicitHeight
            active: ws.hasWindows
            asynchronous: true
            visible: active

            sourceComponent: Column {
                spacing: 0

                add: Transition {
                    Anim {
                        easing: Tokens.anim.standardDecel
                        from: 0
                        properties: "scale"
                        to: 1
                    }
                }
                move: Transition {
                    Anim {
                        easing: Tokens.anim.standardDecel
                        properties: "scale"
                        to: 1
                    }

                    Anim {
                        properties: "x,y"
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: {
                            const windows = Hypr.toplevels.values.filter(c => c.workspace?.id === ws.wsId);
                            const maxIcons = root.Config.bar.workspaces.maxWindowIcons;
                            return maxIcons > 0 ? windows.slice(0, maxIcons) : windows;
                        }
                    }

                    MaterialIcon {
                        required property var modelData

                        color: Colours.palette.m3onSurfaceVariant
                        grade: 0
                        text: Icons.getAppCategoryIcon(modelData.lastIpcObject.class, "terminal")
                    }
                }
            }

            Behavior on Layout.preferredHeight {
                Anim {}
            }
        }
    }
}
