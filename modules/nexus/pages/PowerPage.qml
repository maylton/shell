pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.I18n
import Caelestia.State
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var idle: GlobalConfig.general.idle
    readonly property var timeouts: GlobalConfig.general.idle.timeouts
    readonly property bool hasBattery: UPower.displayDevice.isLaptopBattery

    // The built-in idle timeouts this page manages, found by their idle action.
    // Any other (custom) timeouts in the config are left untouched.
    readonly property var lockEntry: timeouts.values.find(t => actionKind(t.idleAction) === "lock") ?? null
    readonly property var screenEntry: timeouts.values.find(t => actionKind(t.idleAction) === "screen") ?? null
    readonly property var sleepEntry: timeouts.values.find(t => actionKind(t.idleAction) === "sleep") ?? null

    // Timeout presets in seconds, 0 means the action never runs
    readonly property list<int> presets: [0, 60, 120, 180, 300, 600, 900, 1800, 3600]

    readonly property list<MenuItem> sleepModeItems: [
        MenuItem {
            text: Tr.trCtx("Suspend", "sleep mode")
            icon: "bedtime"
            value: "suspend"
        },
        MenuItem {
            text: Tr.trCtx("Suspend, then hibernate", "sleep mode")
            icon: "bedtime"
            value: "suspendThenHibernate"
        },
        MenuItem {
            text: Tr.trCtx("Hibernate", "sleep mode")
            icon: "mode_standby"
            value: "hibernate"
        }
    ]

    function actionName(action: var): string {
        if (!action)
            return "";
        if (typeof action === "string")
            return action;
        // String list command, e.g. ["suspendThenHibernate"] or ["systemctl", "suspend"]
        const first = String(action[0] ?? "");
        if ((first === "systemctl" || first === "loginctl") && action.length === 2)
            return String(action[1]);
        return first;
    }

    function actionKind(action: var): string {
        const name = actionName(action).toLowerCase().replace(/[-_]/g, "");
        if (name === "lock" || name === "locksession")
            return "lock";
        if (name === "dpms off" || name.startsWith("hl.dsp.dpms"))
            return "screen";
        if (["suspend", "suspendthenhibernate", "hibernate"].includes(name))
            return "sleep";
        return "";
    }

    function entryTimeout(entry: var): int {
        return entry && (entry.enabled ?? true) ? entry.timeout : 0;
    }

    function formatTimeout(seconds: int): string {
        if (seconds <= 0)
            return Tr.trCtx("Never", "idle timeout");
        if (seconds % 3600 === 0)
            // TRANSLATORS: h is the hour unit
            return Tr.tr("%1 h").arg(seconds / 3600);
        if (seconds % 60 === 0)
            // TRANSLATORS: min is the minute unit
            return Tr.tr("%1 min").arg(seconds / 60);
        // TRANSLATORS: s is the second unit
        return Tr.tr("%1 s").arg(seconds);
    }

    function setTimeout(kind: string, seconds: int): void {
        let entry = kind === "lock" ? lockEntry : kind === "screen" ? screenEntry : sleepEntry;

        if (!entry) {
            if (seconds <= 0)
                return;

            if (kind === "lock")
                entry = timeouts.insert({
                    idleAction: "lock"
                });
            else if (kind === "screen")
                entry = timeouts.insert({
                    idleAction: "dpms off",
                    returnAction: "dpms on"
                });
            else
                entry = timeouts.insert({
                    idleAction: "suspendThenHibernate"
                });
        }

        if (seconds <= 0) {
            entry.enabled = false;
        } else {
            entry.timeout = seconds;
            entry.enabled = true;
        }
    }

    function setSleepMode(mode: string): void {
        if (sleepEntry) {
            // Stored as a plain string, the idle daemon routes it to the session manager
            sleepEntry.idleAction = mode;
        } else {
            const entry = timeouts.insert({
                idleAction: mode
            });
            entry.enabled = false;
        }
    }

    title: Tr.tr("Power")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Timeout menus, one per action so each can mark its own active item
        Variants {
            id: lockItems

            model: root.presets

            MenuItem {
                required property int modelData

                text: root.formatTimeout(modelData)
                icon: modelData === root.entryTimeout(root.lockEntry) ? "check" : ""
                activeIcon: modelData > 0 ? "lock" : "lock_open"
                value: modelData
            }
        }

        Variants {
            id: screenItems

            model: root.presets

            MenuItem {
                required property int modelData

                text: root.formatTimeout(modelData)
                icon: modelData === root.entryTimeout(root.screenEntry) ? "check" : ""
                activeIcon: modelData > 0 ? "desktop_access_disabled" : "desktop_windows"
                value: modelData
            }
        }

        Variants {
            id: sleepItems

            model: root.presets

            MenuItem {
                required property int modelData

                text: root.formatTimeout(modelData)
                icon: modelData === root.entryTimeout(root.sleepEntry) ? "check" : ""
                activeIcon: modelData > 0 ? "bedtime" : "bedtime_off"
                value: modelData
            }
        }

        // Keep awake
        SectionHeader {
            first: true
            text: Tr.tr("Keep awake")
        }

        ToggleRow {
            first: true
            last: true
            text: Tr.tr("Keep awake")
            subtext: RuntimeState.inhibitIdle ? Tr.tr("Idle actions are paused until you turn this off") : Tr.tr("Pause screen lock, screen off and sleep")
            checked: RuntimeState.inhibitIdle
            onToggled: RuntimeState.inhibitIdle = checked
        }

        // When idle
        SectionHeader {
            text: Tr.tr("When inactive")
        }

        SelectRow {
            first: true
            label: Tr.tr("Lock the screen after")
            subtext: Tr.tr("Time without input before the lock screen shows")
            menuItems: lockItems.instances
            active: menuItems.find(i => i.value === root.entryTimeout(root.lockEntry)) ?? null
            fallbackIcon: "lock"
            fallbackText: root.formatTimeout(root.entryTimeout(root.lockEntry))
            onSelected: item => root.setTimeout("lock", item.value)
        }

        SelectRow {
            label: Tr.tr("Turn off the screen after")
            subtext: Tr.tr("Time without input before displays go to sleep")
            menuItems: screenItems.instances
            active: menuItems.find(i => i.value === root.entryTimeout(root.screenEntry)) ?? null
            fallbackIcon: "desktop_access_disabled"
            fallbackText: root.formatTimeout(root.entryTimeout(root.screenEntry))
            onSelected: item => root.setTimeout("screen", item.value)
        }

        SelectRow {
            label: Tr.tr("Put the system to sleep after")
            subtext: Tr.tr("Time without input before the computer sleeps")
            menuItems: sleepItems.instances
            active: menuItems.find(i => i.value === root.entryTimeout(root.sleepEntry)) ?? null
            fallbackIcon: "bedtime"
            fallbackText: root.formatTimeout(root.entryTimeout(root.sleepEntry))
            onSelected: item => root.setTimeout("sleep", item.value)
        }

        SelectRow {
            last: true
            label: Tr.tr("Sleep mode")
            subtext: Tr.tr("What happens when the system goes to sleep")
            disabled: root.entryTimeout(root.sleepEntry) <= 0
            menuOnTop: true
            menuItems: root.sleepModeItems
            active: {
                const name = root.actionName(root.sleepEntry?.idleAction).toLowerCase().replace(/[-_]/g, "");
                return root.sleepModeItems.find(i => i.value.toLowerCase() === name) ?? root.sleepModeItems[1];
            }
            onSelected: item => root.setSleepMode(item.value)
        }

        // Behaviour
        SectionHeader {
            text: Tr.tr("Behaviour")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Lock before sleeping")
            subtext: Tr.tr("Always lock the screen when the system suspends")
            checked: root.idle.lockBeforeSleep
            onToggled: root.idle.lockBeforeSleep = checked
        }

        ToggleRow {
            last: !root.hasBattery
            text: Tr.tr("Stay awake while media plays")
            subtext: Tr.tr("Don't lock, turn off the screen or sleep during playback")
            checked: root.idle.inhibitWhenAudio
            onToggled: root.idle.inhibitWhenAudio = checked
        }

        ToggleRow {
            last: true
            visible: root.hasBattery
            text: Tr.tr("Stay awake while charging")
            subtext: Tr.tr("Don't run idle actions when plugged in")
            checked: root.idle.inhibitWhenCharging
            onToggled: root.idle.inhibitWhenCharging = checked
        }
    }
}
