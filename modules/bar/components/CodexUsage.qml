pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services as CServices
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    readonly property QtObject codexUsageRef: CServices.ServiceRef {
        service: CServices.CodexUsage
    }
    readonly property bool fiveVisible: Config.bar.codexUsage.showFiveHour && CServices.CodexUsage.available && (CServices.CodexUsage.fiveHour.available ?? false)
    readonly property bool hasAnyRing: fiveVisible || weeklyVisible
    readonly property color inactiveColour: Colours.palette.m3outline
    readonly property bool weeklyVisible: Config.bar.codexUsage.showWeekly && CServices.CodexUsage.available && (CServices.CodexUsage.weekly.available ?? false)

    clip: true
    color: Colours.tPalette.m3surfaceContainer
    implicitHeight: Math.max(Tokens.sizes.bar.innerWidth, layout.implicitHeight + Tokens.padding.small * 2)
    implicitWidth: Tokens.sizes.bar.innerWidth
    radius: Tokens.rounding.full

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall
        width: parent.width

        Loader {
            Layout.alignment: Qt.AlignHCenter
            active: root.fiveVisible
            visible: active

            sourceComponent: UsageRing {
                icon: "timer"
                percent: (CServices.CodexUsage.fiveHour.usedPercent ?? 0)
                ringColour: Colours.palette.m3primary
            }
        }

        Loader {
            Layout.alignment: Qt.AlignHCenter
            active: root.weeklyVisible
            visible: active

            sourceComponent: UsageRing {
                icon: "calendar_month"
                percent: (CServices.CodexUsage.weekly.usedPercent ?? 0)
                ringColour: Colours.palette.m3tertiary
            }
        }

        Loader {
            Layout.alignment: Qt.AlignHCenter
            active: !root.hasAnyRing
            visible: active

            sourceComponent: MaterialIcon {
                color: root.inactiveColour
                fontStyle: Tokens.font.icon.small
                text: "code"
            }
        }
    }

    component UsageRing: CircularProgress {
        id: ring

        required property string icon
        required property real percent
        required property color ringColour

        bgColour: Qt.alpha(fgColour, 0.2)
        fgColour: percent >= 95 ? Colours.palette.m3error : ringColour
        hasEndIndicator: false
        implicitSize: Tokens.sizes.bar.innerWidth - Tokens.padding.small * 2
        strokeWidth: Math.max(2, Math.round(Tokens.padding.extraSmall))
        value: Math.max(0, Math.min(100, percent)) / 100

        Behavior on clampedVal {
            Anim {}
        }

        MaterialIcon {
            anchors.centerIn: parent
            color: ring.fgColour
            fontStyle: Tokens.font.icon.small
            scale: 0.85
            text: ring.icon
        }
    }
}
