pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services as CServices
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> accountDisplayItems: [
        MenuItem {
            text: qsTr("Masked email")
            icon: "alternate_email"
            value: "maskedEmail"
        },
        MenuItem {
            text: qsTr("Full email")
            icon: "badge"
            value: "fullEmail"
        },
        MenuItem {
            text: qsTr("Plan only")
            icon: "workspace_premium"
            value: "planOnly"
        }
    ]

    readonly property list<MenuItem> pricingBasisItems: [
        MenuItem {
            text: qsTr("Detected model")
            icon: "data_object"
            value: "detectedModel"
        },
        MenuItem {
            text: qsTr("GPT-5.5")
            icon: "api"
            value: "gpt-5.5"
        },
        MenuItem {
            text: qsTr("Codex model")
            icon: "code"
            value: "codexModel"
        }
    ]

    readonly property list<MenuItem> monthlyWindowItems: [
        MenuItem {
            text: qsTr("Calendar month")
            icon: "calendar_month"
            value: "calendarMonth"
        },
        MenuItem {
            text: qsTr("Rolling 30 days")
            icon: "history"
            value: "rolling30Days"
        }
    ]

    function entryIndex(): int {
        return GlobalConfig.bar.entries.findIndex(e => e.id === "codexUsage");
    }

    function entryEnabled(): bool {
        const idx = entryIndex();
        return idx >= 0 && (GlobalConfig.bar.entries[idx].enabled ?? true) && GlobalConfig.bar.codexUsage.enabled;
    }

    function copyEntry(entry: var): var {
        const copy = {};
        Object.keys(entry).forEach(k => {
            copy[k] = entry[k];
        });
        return copy;
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

    function activeItem(items: var, value: string): MenuItem {
        return items.find(i => i.value === value) ?? items[0];
    }

    title: qsTr("Codex usage")
    isSubPage: true

    readonly property QtObject codexUsageRef: CServices.ServiceRef {
        service: CServices.CodexUsage
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Taskbar
        SectionHeader {
            first: true
            text: qsTr("Taskbar")
        }

        ToggleRow {
            first: true
            text: qsTr("Show Codex usage")
            subtext: CServices.CodexUsage.status
            checked: root.entryEnabled()
            onToggled: root.setEntryEnabled(checked)
        }

        ToggleRow {
            text: qsTr("Popout on hover")
            subtext: qsTr("Show account, token, reset, and pricing details")
            checked: GlobalConfig.bar.popouts.codexUsage
            onToggled: GlobalConfig.bar.popouts.codexUsage = checked
        }

        ToggleRow {
            text: qsTr("5-hour ring")
            subtext: qsTr("Use Codex's reported 300-minute rate-limit window")
            checked: GlobalConfig.bar.codexUsage.showFiveHour
            onToggled: GlobalConfig.bar.codexUsage.showFiveHour = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Weekly ring")
            subtext: qsTr("Use Codex's reported 10080-minute rate-limit window")
            checked: GlobalConfig.bar.codexUsage.showWeekly
            onToggled: GlobalConfig.bar.codexUsage.showWeekly = checked
        }

        // Data
        SectionHeader {
            text: qsTr("Data")
        }

        M3TextField {
            id: codexHome

            Layout.fillWidth: true
            label: qsTr("Codex home")
            placeholder: "~/.codex"
            leadingIcon: "folder"
            text: GlobalConfig.bar.codexUsage.codexHome
            supportingText: qsTr("Leave empty to use CODEX_HOME or ~/.codex")
            inputMethodHints: Qt.ImhNoPredictiveText
            onAccepted: GlobalConfig.bar.codexUsage.codexHome = text.trim()
        }

        Connections {
            target: codexHome.field
            function onEditingFinished(): void {
                GlobalConfig.bar.codexUsage.codexHome = codexHome.text.trim();
            }
        }

        StepperRow {
            label: qsTr("Refresh interval")
            subtext: qsTr("Seconds between local Codex usage refreshes")
            value: GlobalConfig.bar.codexUsage.refreshIntervalSeconds
            from: 5
            to: 300
            stepSize: 5
            onMoved: v => GlobalConfig.bar.codexUsage.refreshIntervalSeconds = Math.round(v)
        }

        SelectRow {
            label: qsTr("Account display")
            subtext: qsTr("Masking keeps the tooltip safe for screenshots")
            menuItems: root.accountDisplayItems
            active: root.activeItem(root.accountDisplayItems, GlobalConfig.bar.codexUsage.accountDisplay)
            onSelected: item => GlobalConfig.bar.codexUsage.accountDisplay = item.value
        }

        SelectRow {
            label: qsTr("Pricing basis")
            subtext: qsTr("Model used for the API equivalent")
            menuItems: root.pricingBasisItems
            active: root.activeItem(root.pricingBasisItems, GlobalConfig.bar.codexUsage.pricingBasis)
            onSelected: item => GlobalConfig.bar.codexUsage.pricingBasis = item.value
        }

        SelectRow {
            label: qsTr("Monthly window")
            subtext: qsTr("Range used for the token and dollar totals")
            menuItems: root.monthlyWindowItems
            active: root.activeItem(root.monthlyWindowItems, GlobalConfig.bar.codexUsage.monthlyWindow)
            onSelected: item => GlobalConfig.bar.codexUsage.monthlyWindow = item.value
        }

        ToggleRow {
            last: true
            text: qsTr("API equivalent")
            subtext: qsTr("Show the monthly standard API price comparison")
            checked: GlobalConfig.bar.codexUsage.showSavings
            onToggled: GlobalConfig.bar.codexUsage.showSavings = checked
        }
    }
}
