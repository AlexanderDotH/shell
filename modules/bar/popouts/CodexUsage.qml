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
        return Qt.formatDateTime(new Date(seconds * 1000), GlobalConfig.services.useTwelveHourClock ? "MMM d, h:mm A" : "MMM d, HH:mm");
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

    spacing: Tokens.spacing.medium
    width: 320

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
        visible: !CServices.CodexUsage.available
        text: CServices.CodexUsage.status
        color: Colours.palette.m3error
        font: Tokens.font.label.small
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        UsageWindow {
            Layout.fillWidth: true
            label: qsTr("5h")
            icon: "timer"
            colour: Colours.palette.m3primary
            usageData: CServices.CodexUsage.fiveHour
        }

        UsageWindow {
            Layout.fillWidth: true
            label: qsTr("Week")
            icon: "calendar_month"
            colour: Colours.palette.m3tertiary
            usageData: CServices.CodexUsage.weekly
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
                text: qsTr("Reset %1").arg(root.formatReset(usage.usageData?.resetsAt))
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
