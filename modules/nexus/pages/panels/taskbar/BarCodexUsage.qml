pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services as CServices
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property QtObject codexUsageRef: CServices.ServiceRef {
        service: CServices.CodexUsage
    }
    readonly property list<MenuItem> accountDisplayItems: [
        MenuItem {
            icon: "alternate_email"
            text: qsTr("Masked email")
            value: "maskedEmail"
        },
        MenuItem {
            icon: "badge"
            text: qsTr("Full email")
            value: "fullEmail"
        },
        MenuItem {
            icon: "workspace_premium"
            text: qsTr("Plan only")
            value: "planOnly"
        }
    ]
    readonly property list<MenuItem> monthlyWindowItems: [
        MenuItem {
            icon: "calendar_month"
            text: qsTr("Calendar month")
            value: "calendarMonth"
        },
        MenuItem {
            icon: "history"
            text: qsTr("Rolling 30 days")
            value: "rolling30Days"
        }
    ]
    readonly property list<MenuItem> pricingBasisItems: [
        MenuItem {
            icon: "data_object"
            text: qsTr("Detected model")
            value: "detectedModel"
        },
        MenuItem {
            icon: "api"
            text: qsTr("GPT-5.6 Sol")
            value: "gpt-5.6-sol"
        },
        MenuItem {
            icon: "balance"
            text: qsTr("GPT-5.6 Terra")
            value: "gpt-5.6-terra"
        },
        MenuItem {
            icon: "savings"
            text: qsTr("GPT-5.6 Luna")
            value: "gpt-5.6-luna"
        },
        MenuItem {
            icon: "api"
            text: qsTr("GPT-5.5")
            value: "gpt-5.5"
        },
        MenuItem {
            icon: "code"
            text: qsTr("Codex model")
            value: "codexModel"
        }
    ]

    function copyEntry(entry: var): var {
        const copy = {};
        Object.keys(entry).forEach(k => {
            copy[k] = entry[k];
        });
        return copy;
    }

    function entryEnabled(): bool {
        const idx = entryIndex();
        return idx >= 0 && (GlobalConfig.bar.entries[idx].enabled ?? true) && GlobalConfig.bar.codexUsage.enabled;
    }

    function entryIndex(): int {
        return GlobalConfig.bar.entries.findIndex(e => e.id === "codexUsage");
    }

    function setEntryEnabled(enabled: bool): void {
        const entries = GlobalConfig.bar.entries.map(e => root.copyEntry(e));
        let idx = entries.findIndex(e => e.id === "codexUsage");
        if (idx < 0 && enabled) {
            const statusIdx = entries.findIndex(e => e.id === "statusIcons");
            idx = statusIdx >= 0 ? statusIdx : entries.length;
            entries.splice(idx, 0, {
                id: "codexUsage",
                enabled: true
            });
        } else if (idx >= 0) {
            entries[idx].enabled = enabled;
        }
        GlobalConfig.bar.entries = entries;
        GlobalConfig.bar.codexUsage.enabled = enabled;
    }

    isSubPage: true
    title: qsTr("Codex usage")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        spacing: Tokens.spacing.extraSmall / 2
        width: root.cappedWidth

        // Taskbar
        SectionHeader {
            first: true
            text: qsTr("Taskbar")
        }

        ToggleRow {
            checked: root.entryEnabled()
            first: true
            subtext: CServices.CodexUsage.status
            text: qsTr("Show Codex usage")

            onToggled: root.setEntryEnabled(checked)
        }

        ToggleRow {
            checked: GlobalConfig.bar.popouts.codexUsage
            subtext: qsTr("Show account, token, reset, and pricing details")
            text: qsTr("Popout on hover")

            onToggled: GlobalConfig.bar.popouts.codexUsage = checked
        }

        ToggleRow {
            checked: GlobalConfig.bar.codexUsage.showFiveHour
            subtext: qsTr("Use Codex's reported 300-minute rate-limit window")
            text: qsTr("5-hour ring")

            onToggled: GlobalConfig.bar.codexUsage.showFiveHour = checked
        }

        ToggleRow {
            checked: GlobalConfig.bar.codexUsage.showWeekly
            last: true
            subtext: qsTr("Use Codex's reported 10080-minute rate-limit window")
            text: qsTr("Weekly ring")

            onToggled: GlobalConfig.bar.codexUsage.showWeekly = checked
        }

        // Data
        SectionHeader {
            text: qsTr("Data")
        }

        StyledTextField {
            id: codexHome

            Layout.fillWidth: true
            inputMethodHints: Qt.ImhNoPredictiveText
            leadingIcon: "folder"
            placeholderText: qsTr("Codex home")
            supportingText: qsTr("Leave empty to use CODEX_HOME or ~/.codex")
            text: GlobalConfig.bar.codexUsage.codexHome

            onEditingFinished: GlobalConfig.bar.codexUsage.codexHome = codexHome.text.trim()
        }

        StepperRow {
            from: 5
            label: qsTr("Refresh interval")
            stepSize: 5
            subtext: qsTr("Seconds between local Codex usage refreshes")
            to: 300
            value: GlobalConfig.bar.codexUsage.refreshIntervalSeconds

            onMoved: v => GlobalConfig.bar.codexUsage.refreshIntervalSeconds = Math.round(v)
        }

        SelectRow {
            active: root.accountDisplayItems.find(item => item.value === GlobalConfig.bar.codexUsage.accountDisplay) ?? root.accountDisplayItems[0]
            label: qsTr("Account display")
            menuItems: root.accountDisplayItems
            subtext: qsTr("Masking keeps the tooltip safe for screenshots")

            onSelected: item => GlobalConfig.bar.codexUsage.accountDisplay = item.value
        }

        SelectRow {
            active: root.pricingBasisItems.find(item => item.value === GlobalConfig.bar.codexUsage.pricingBasis) ?? root.pricingBasisItems[0]
            label: qsTr("Pricing basis")
            menuItems: root.pricingBasisItems
            subtext: qsTr("Model used for the API equivalent")

            onSelected: item => GlobalConfig.bar.codexUsage.pricingBasis = item.value
        }

        SelectRow {
            active: root.monthlyWindowItems.find(item => item.value === GlobalConfig.bar.codexUsage.monthlyWindow) ?? root.monthlyWindowItems[0]
            label: qsTr("Monthly window")
            menuItems: root.monthlyWindowItems
            subtext: qsTr("Range used for the token and dollar totals")

            onSelected: item => GlobalConfig.bar.codexUsage.monthlyWindow = item.value
        }

        ToggleRow {
            checked: GlobalConfig.bar.codexUsage.showSavings
            last: true
            subtext: qsTr("Show the monthly standard API price comparison")
            text: qsTr("API equivalent")

            onToggled: GlobalConfig.bar.codexUsage.showSavings = checked
        }
    }
}
