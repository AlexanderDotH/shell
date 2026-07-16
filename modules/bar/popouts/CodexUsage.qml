pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.Services as CServices
import qs.components
import qs.services

ColumnLayout {
    id: root

    property double nowEpoch: Date.now() / 1000
    readonly property bool hasAnyLimit: CServices.CodexUsage.available && ((CServices.CodexUsage.fiveHour.available ?? false) || (CServices.CodexUsage.weekly.available ?? false))
    readonly property var resetData: CServices.CodexUsage.rateLimitResets
    readonly property string resetState: resetData.state ?? "loading"
    readonly property int resetCount: Number(resetData.availableCount ?? 0)

    readonly property QtObject codexUsageRef: CServices.ServiceRef {
        service: CServices.CodexUsage
    }

    function formatTokens(value: var): string {
        const n = Number(value ?? 0);
        if (n >= 1000000000)
            return `${(n / 1000000000).toFixed(2)}B`;
        if (n >= 1000000)
            return `${(n / 1000000).toFixed(2)}M`;
        if (n >= 1000)
            return `${(n / 1000).toFixed(1)}K`;
        return `${Math.round(n)}`;
    }

    function formatPercent(value: var): string {
        return `${Math.round(Number(value ?? 0))}%`;
    }

    function formatReset(epoch: var): string {
        const seconds = Number(epoch ?? 0);
        if (seconds <= 0)
            return qsTr("Unknown");
        const remainingMinutes = Math.max(0, Math.ceil((seconds - root.nowEpoch) / 60));
        if (remainingMinutes === 0)
            return qsTr("now");
        const days = Math.floor(remainingMinutes / 1440);
        const hours = Math.floor((remainingMinutes % 1440) / 60);
        const minutes = remainingMinutes % 60;
        const parts = [];
        if (days > 0)
            parts.push(qsTr("%1d").arg(days));
        if (hours > 0)
            parts.push(qsTr("%1h").arg(hours));
        if (days === 0 && minutes > 0)
            parts.push(qsTr("%1m").arg(minutes));
        return qsTr("in %1").arg(parts.join(" "));
    }

    function authLine(): string {
        const account = CServices.CodexUsage.accountLabel || qsTr("Unknown account");
        const plan = CServices.CodexUsage.planLabel;
        const workspace = CServices.CodexUsage.workspaceLabel;
        const parts = [account];
        if (plan)
            parts.push(plan);
        if (workspace)
            parts.push(workspace);
        return parts.join("  |  ");
    }

    function resetExpiry(): string {
        const credits = root.resetData.credits ?? [];
        let earliest = 0;
        for (let i = 0; i < credits.length; i++) {
            const expiresAt = Number(credits[i]?.expiresAt ?? 0);
            if (expiresAt > root.nowEpoch && (earliest === 0 || expiresAt < earliest))
                earliest = expiresAt;
        }
        return earliest > 0 ? qsTr("Expires %1").arg(Qt.formatDateTime(new Date(earliest * 1000), "MMM d")) : "";
    }

    spacing: Tokens.spacing.medium
    width: 320

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.nowEpoch = Date.now() / 1000
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        MaterialIcon {
            Layout.alignment: Qt.AlignVCenter
            text: "code"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.large
            fill: 1
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Codex usage")
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.authLine()
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: CServices.CodexUsage.status !== "OK"
        text: CServices.CodexUsage.status
        color: CServices.CodexUsage.available ? Colours.palette.m3outline : Colours.palette.m3error
        font: Tokens.font.label.small
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.hasAnyLimit
        spacing: Tokens.spacing.medium

        UsageWindow {
            Layout.fillWidth: true
            visible: CServices.CodexUsage.available && (CServices.CodexUsage.fiveHour.available ?? false)
            label: qsTr("5h")
            icon: "timer"
            colour: Colours.palette.m3primary
            usageData: CServices.CodexUsage.fiveHour
        }

        UsageWindow {
            Layout.fillWidth: true
            visible: CServices.CodexUsage.available && (CServices.CodexUsage.weekly.available ?? false)
            label: qsTr("Week")
            icon: "calendar_month"
            colour: Colours.palette.m3tertiary
            usageData: CServices.CodexUsage.weekly
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: resetLayout.implicitHeight + Tokens.padding.small * 2
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large

        RowLayout {
            id: resetLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "restart_alt"
                color: Colours.palette.m3outline
                fontStyle: Tokens.font.icon.small
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Full resets")
                    font: Tokens.font.label.builders.small.weight(Font.Medium).build()
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.resetExpiry()
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }

            StyledRect {
                implicitWidth: resetCountLabel.implicitWidth + Tokens.padding.medium
                implicitHeight: resetCountLabel.implicitHeight + Tokens.padding.extraSmall * 2
                color: Colours.tPalette.m3surfaceContainerHighest
                radius: Tokens.rounding.full

                StyledText {
                    id: resetCountLabel

                    anchors.centerIn: parent
                    text: root.resetState === "ready"
                        ? (root.resetCount === 1 ? qsTr("1 available") : qsTr("%1 available").arg(root.resetCount))
                        : (root.resetState === "loading" ? qsTr("Checking…") : qsTr("Unavailable"))
                    color: root.resetState === "ready" ? Colours.palette.m3onSurface : Colours.palette.m3outline
                    font: Tokens.font.label.builders.small.weight(Font.Medium).build()
                }
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: tokenLayout.implicitHeight + Tokens.padding.medium * 2
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large

        ColumnLayout {
            id: tokenLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            DetailRow {
                label: qsTr("Input")
                value: root.formatTokens(CServices.CodexUsage.monthlyTokens.inputTokens)
            }

            DetailRow {
                label: qsTr("Cached input")
                value: root.formatTokens(CServices.CodexUsage.monthlyTokens.cachedInputTokens)
            }

            DetailRow {
                label: qsTr("Output")
                value: root.formatTokens(CServices.CodexUsage.monthlyTokens.outputTokens)
            }

            DetailRow {
                label: qsTr("Reasoning")
                value: root.formatTokens(CServices.CodexUsage.monthlyTokens.reasoningOutputTokens)
            }

            DetailRow {
                label: qsTr("Total")
                value: root.formatTokens(CServices.CodexUsage.monthlyTokens.totalTokens)
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        visible: Config.bar.codexUsage.showSavings
        implicitHeight: savingsLayout.implicitHeight + Tokens.padding.medium * 2
        color: Colours.palette.m3secondaryContainer
        radius: Tokens.rounding.large

        ColumnLayout {
            id: savingsLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "attach_money"
                    color: Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("API equivalent this month")
                    color: Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }

                StyledText {
                    text: CServices.CodexUsage.monthlyApiDollarsText
                    color: Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Comparison only, based on standard API token pricing.")
                color: Qt.alpha(Colours.palette.m3onSecondaryContainer, 0.78)
                font: Tokens.font.label.small
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Model breakdown")
                color: Colours.palette.m3onSecondaryContainer
                font: Tokens.font.label.builders.small.weight(Font.Medium).build()
            }

            Repeater {
                model: ScriptModel {
                    values: CServices.CodexUsage.modelCostBreakdown
                }

                delegate: DetailRow {
                    required property var modelData

                    label: modelData.mapped ? `${modelData.model} -> ${modelData.pricedModel}` : modelData.model
                    value: modelData.priced ? modelData.dollarsText : qsTr("Unpriced")
                    labelColour: Qt.alpha(Colours.palette.m3onSecondaryContainer, 0.78)
                    valueColour: Colours.palette.m3onSecondaryContainer
                }
            }

        }
    }

    StyledText {
        Layout.fillWidth: true
        text: qsTr("Updated %1").arg(CServices.CodexUsage.lastUpdated > 0 ? Qt.formatDateTime(new Date(CServices.CodexUsage.lastUpdated * 1000), GlobalConfig.services.useTwelveHourClock ? "h:mm:ss A" : "HH:mm:ss") : qsTr("never"))
        color: Colours.palette.m3outline
        font: Tokens.font.label.small
        elide: Text.ElideRight
    }

    component UsageWindow: StyledRect {
        id: usage

        required property string label
        required property string icon
        required property color colour
        property var usageData

        implicitHeight: usageLayout.implicitHeight + Tokens.padding.medium * 2
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large

        ColumnLayout {
            id: usageLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: usage.icon
                    color: usage.colour
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: usage.label
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }

            StyledText {
                text: root.formatPercent(usage.usageData?.usedPercent)
                color: usage.usageData?.usedPercent >= 95 ? Colours.palette.m3error : usage.colour
                font: Tokens.font.title.medium
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Renews %1").arg(root.formatReset(usage.usageData?.resetsAt))
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }
    }

    component DetailRow: RowLayout {
        required property string label
        required property string value
        property color labelColour: Colours.palette.m3outline
        property color valueColour: Colours.palette.m3onSurface

        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.fillWidth: true
            text: parent.label
            color: parent.labelColour
            font: Tokens.font.label.small
            elide: Text.ElideRight
        }

        StyledText {
            text: parent.value
            color: parent.valueColour
            font: Tokens.font.label.builders.small.weight(Font.Medium).build()
            elide: Text.ElideRight
        }
    }
}
