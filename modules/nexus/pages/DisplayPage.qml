pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property int revertSeconds: 15
    readonly property string savedPath: `${Paths.config}/nexus-monitors.json`
    readonly property string luaPath: `${Paths.config}/hypr-monitors.lua`

    property list<var> monitors: []
    property string selectedName
    readonly property var mon: monitors.find(m => m.name === selectedName) ?? monitors.find(m => m.focused) ?? monitors[0] ?? null
    readonly property int enabledCount: monitors.filter(m => !m.disabled).length
    readonly property bool multi: monitors.length > 1

    // Saved rules keyed by output name plus the primary monitor, mirrored into hypr-monitors.lua
    property var saved: ({
            rules: {},
            primary: ""
        })
    property bool includedInConfig: true

    // Hyprland has no primary monitor, so fall back to the one at the layout origin
    readonly property string primaryName: saved.primary || monitors.find(m => !m.disabled && m.x === 0 && m.y === 0)?.name || monitors[0]?.name || ""
    readonly property var primaryMon: monitors.find(m => m.name === primaryName) ?? null
    readonly property bool isPrimary: mon?.name === primaryName

    // Pending edits for the selected monitor, see valuesOf()
    property var pending: ({})

    // Rule last applied, and the one to restore if it isn't confirmed in time
    property var appliedRule: null
    property var revertRule: null
    property int countdown
    property string error

    readonly property list<var> modes: (mon?.availableModes ?? []).map(s => s.match(/^(\d+)x(\d+)@([\d.]+)Hz$/)).filter(m => m).map(m => ({
                res: `${m[1]}x${m[2]}`,
                area: m[1] * m[2],
                rate: m[3]
            }))
    readonly property list<string> resolutions: [...new Set([...modes].sort((a, b) => b.area - a.area).map(m => m.res))]
    readonly property list<string> rates: ratesFor(pending.res)

    readonly property var pendingRule: mon ? ruleFrom(mon.name, pending) : null
    readonly property bool dirty: mon !== null && JSON.stringify(pendingRule) !== JSON.stringify(ruleFrom(mon.name, valuesOf(mon)))
    readonly property bool hdrRejected: appliedRule !== null && appliedRule.output === mon?.name && appliedRule.cm === "hdr" && !valuesOf(mon).hdr

    // Quick placements next to the primary monitor, in logical pixels
    readonly property list<var> placements: {
        if (!primaryMon || isPrimary || !pending.res)
            return [];
        const p = logicalSize(`${primaryMon.width}x${primaryMon.height}`, primaryMon.scale, primaryMon.transform);
        const s = logicalSize(pending.res, pending.scale, pending.transform);
        return [
            {
                text: Tr.trCtx("Right of primary", "monitor placement"),
                x: primaryMon.x + p.w,
                y: primaryMon.y
            },
            {
                text: Tr.trCtx("Left of primary", "monitor placement"),
                x: primaryMon.x - s.w,
                y: primaryMon.y
            },
            {
                text: Tr.trCtx("Above primary", "monitor placement"),
                x: primaryMon.x,
                y: primaryMon.y - s.h
            },
            {
                text: Tr.trCtx("Below primary", "monitor placement"),
                x: primaryMon.x,
                y: primaryMon.y + p.h
            }
        ];
    }

    function round2(v: real): real {
        return Math.round(v * 100) / 100;
    }

    function ratesFor(res: string): list<string> {
        return [...new Set(modes.filter(m => m.res === res).map(m => m.rate))].sort((a, b) => b - a);
    }

    function logicalSize(res: string, scale: real, transform: int): var {
        const [w, h] = res.split("x").map(Number);
        const rotated = transform % 2 === 1;
        return {
            w: Math.round((rotated ? h : w) / scale),
            h: Math.round((rotated ? w : h) / scale)
        };
    }

    // Closest available rate for a monitor's current mode
    function currentRate(m: var): string {
        const candidates = ratesFor(`${m.width}x${m.height}`);
        if (candidates.length === 0)
            return m.refreshRate.toFixed(2);
        return candidates.reduce((best, r) => Math.abs(r - m.refreshRate) < Math.abs(best - m.refreshRate) ? r : best);
    }

    // Editable settings of a monitor as Hyprland currently reports them
    function valuesOf(m: var): var {
        // Hyprland only reports whether VRR is active, so prefer the configured value
        const configured = appliedRule?.output === m.name ? appliedRule : saved.rules[m.name];
        return {
            enabled: !m.disabled,
            res: m.disabled ? (resolutions[0] ?? "") : `${m.width}x${m.height}`,
            rate: m.disabled ? (ratesFor(resolutions[0])[0] ?? "") : currentRate(m),
            scale: round2(m.scale),
            transform: m.transform,
            vrr: configured?.vrr ?? (m.vrr ? 1 : 0),
            hdr: ["hdr", "hdredid"].includes(m.colorManagementPreset),
            sdrBrightness: round2(m.sdrBrightness ?? 1),
            sdrSaturation: round2(m.sdrSaturation ?? 1),
            // mirrorOf is the mirrored monitor's id
            mirror: monitors.find(o => String(o.id) === String(m.mirrorOf))?.name ?? "",
            x: m.x,
            y: m.y
        };
    }

    // Hyprland merges a rule into the output's previous one, so every field is always set
    function ruleFrom(name: string, v: var): var {
        if (!v.enabled)
            return {
                output: name,
                disabled: true
            };
        return {
            output: name,
            disabled: false,
            mode: `${v.res}@${v.rate}`,
            position: `${v.x}x${v.y}`,
            scale: round2(v.scale),
            transform: v.transform,
            vrr: v.vrr,
            mirror: v.mirror,
            cm: v.hdr ? "hdr" : "auto",
            bitdepth: v.hdr ? 10 : 8,
            sdrbrightness: v.hdr ? round2(v.sdrBrightness) : 1,
            sdrsaturation: v.hdr ? round2(v.sdrSaturation) : 1
        };
    }

    function set(key: string, value: var): void {
        const p = Object.assign({}, pending);
        p[key] = value;
        if (key === "res" && !ratesFor(value).includes(p.rate))
            p.rate = ratesFor(value)[0] ?? "";
        pending = p;
    }

    function toLua(rule: var): string {
        const fields = Object.entries(rule).map(([k, v]) => `${k} = ${typeof v === "string" ? JSON.stringify(v) : v}`);
        return `hl.monitor({ ${fields.join(", ")} })`;
    }

    // Statements that make a monitor the primary one; xrandr sets the XWayland primary output used by games
    function primaryLua(name: string): string {
        const xrandr = JSON.stringify(`sh -c 'sleep 2; xrandr --output ${name} --primary'`);
        return [`hl.config({ cursor = { default_monitor = ${JSON.stringify(name)} } })`, `hl.workspace_rule({ workspace = "1", monitor = ${JSON.stringify(name)}, default = true })`, `hl.on("hyprland.start", function() hl.exec_cmd(${xrandr}) end)`, `hl.on("monitor.added", function() hl.exec_cmd(${xrandr}) end)`].join("\n");
    }

    function resetPending(): void {
        if (mon)
            pending = valuesOf(mon);
    }

    function evalRule(rule: var): void {
        error = "";
        evalProc.command = ["hyprctl", "eval", toLua(rule)];
        evalProc.running = true;
    }

    function apply(): void {
        revertRule = ruleFrom(mon.name, valuesOf(mon));
        appliedRule = pendingRule;
        evalRule(appliedRule);
        countdown = revertSeconds;
        countdownTimer.restart();
    }

    function keep(): void {
        countdownTimer.stop();
        revertRule = null;
        const rules = Object.assign({}, saved.rules);
        rules[appliedRule.output] = appliedRule;
        // Pin the other monitors too, or Hyprland's default "auto" position can shuffle the layout on login
        for (const m of monitors)
            if (!rules[m.name] && !m.disabled)
                rules[m.name] = ruleFrom(m.name, valuesOf(m));
        saved = Object.assign({}, saved, {
            rules
        });
        save();
    }

    function revert(): void {
        countdownTimer.stop();
        if (revertRule)
            evalRule(revertRule);
        revertRule = null;
        appliedRule = null;
    }

    // Takes effect right away; nothing here can leave a screen unusable
    function setPrimary(name: string): void {
        saved = Object.assign({}, saved, {
            primary: name
        });
        save();
        // hyprctl eval prepends "return", so wrap the statements in a function
        primaryProc.exec(["hyprctl", "eval", `(function() hl.config({ cursor = { default_monitor = ${JSON.stringify(name)} } }); hl.workspace_rule({ workspace = "1", monitor = ${JSON.stringify(name)}, default = true }) end)()`]);
        Quickshell.execDetached(["xrandr", "--output", name, "--primary"]);
    }

    function save(): void {
        savedFile.setText(JSON.stringify(saved, null, 4));
        const lines = ["-- Generated by the Caelestia Nexus Display page. Changes here are overwritten.", ...Object.values(saved.rules).map(r => toLua(r))];
        if (saved.primary)
            lines.push("", "-- Primary monitor", primaryLua(saved.primary));
        luaFile.setText(lines.join("\n") + "\n");
    }

    function refresh(): void {
        monitorsProc.running = true;
    }

    title: Tr.tr("Display")

    onMonChanged: resetPending()

    Component.onCompleted: refresh()
    // Never leave unconfirmed settings applied
    Component.onDestruction: {
        if (revertRule)
            Quickshell.execDetached(["hyprctl", "eval", toLua(revertRule)]);
    }

    // Ordered to match Hyprland's transform values
    readonly property list<MenuItem> transformItems: [
        MenuItem {
            text: Tr.trCtx("Normal", "display rotation")
        },
        MenuItem {
            text: "90°"
        },
        MenuItem {
            text: "180°"
        },
        MenuItem {
            text: "270°"
        },
        MenuItem {
            text: Tr.trCtx("Flipped", "display rotation")
        },
        MenuItem {
            text: Tr.trCtx("Flipped 90°", "display rotation")
        },
        MenuItem {
            text: Tr.trCtx("Flipped 180°", "display rotation")
        },
        MenuItem {
            text: Tr.trCtx("Flipped 270°", "display rotation")
        }
    ]

    // Ordered to match Hyprland's vrr values
    readonly property list<MenuItem> vrrItems: [
        MenuItem {
            text: Tr.trCtx("Off", "variable refresh rate")
        },
        MenuItem {
            text: Tr.trCtx("On", "variable refresh rate")
        },
        MenuItem {
            text: Tr.trCtx("Fullscreen only", "variable refresh rate")
        }
    ]

    readonly property list<MenuItem> displayModeItems: [
        MenuItem {
            text: Tr.trCtx("Extend", "multi-monitor mode")
            icon: "splitscreen_right"
        },
        MenuItem {
            text: Tr.trCtx("Mirror primary", "multi-monitor mode")
            icon: "content_copy"
        }
    ]

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            id: monitorsProc

            command: ["hyprctl", "monitors", "all", "-j"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        root.monitors = JSON.parse(text);
                        root.resetPending();
                    } catch (e) {
                        root.error = Tr.tr("Unable to read monitors");
                    }
                }
            }
        }

        Process {
            id: evalProc

            stdout: StdioCollector {
                onStreamFinished: {
                    if (text.trim() !== "ok")
                        root.error = text.trim();
                    refreshTimer.restart();
                }
            }
        }

        Process {
            id: primaryProc

            stdout: StdioCollector {
                onStreamFinished: {
                    if (text.trim() !== "ok")
                        root.error = text.trim();
                }
            }
        }

        // Give Hyprland a moment to apply the mode before reading it back
        Timer {
            id: refreshTimer

            interval: 500
            onTriggered: root.refresh()
        }

        Timer {
            id: countdownTimer

            interval: 1000
            repeat: true
            onTriggered: {
                if (--root.countdown <= 0)
                    root.revert();
            }
        }

        Connections {
            function onRawEvent(event: HyprlandEvent): void {
                if (["monitoradded", "monitorremoved", "configreloaded"].includes(event.name))
                    refreshTimer.restart();
            }

            target: Hyprland
        }

        FileView {
            id: savedFile

            printErrors: false
            path: root.savedPath
            onLoaded: {
                try {
                    const data = JSON.parse(text());
                    root.saved = {
                        rules: data.rules ?? {},
                        primary: data.primary ?? ""
                    };
                    root.resetPending();
                } catch (e) {
                    console.warn(`Unable to parse ${root.savedPath}: ${e}`);
                }
            }
        }

        FileView {
            id: luaFile

            printErrors: false
            path: root.luaPath
        }

        // Saved rules only survive a Hyprland restart if the user config loads them
        FileView {
            printErrors: false
            path: `${Paths.config}/hypr-user.lua`
            watchChanges: true
            onFileChanged: reload()
            onLoaded: root.includedInConfig = text().includes("hypr-monitors")
            onLoadFailed: root.includedInConfig = false
        }

        Variants {
            id: monitorItems

            model: root.monitors.map(m => m.name)

            MenuItem {
                required property string modelData

                text: modelData
                icon: modelData === root.mon?.name ? "check" : ""
                activeIcon: "monitor"
            }
        }

        Variants {
            id: primaryItems

            model: root.monitors.filter(m => !m.disabled).map(m => m.name)

            MenuItem {
                required property string modelData

                text: modelData
                icon: modelData === root.primaryName ? "check" : ""
                activeIcon: "star"
            }
        }

        Variants {
            id: resItems

            model: root.resolutions

            MenuItem {
                required property string modelData

                text: modelData.replace("x", " × ")
                value: modelData
                icon: modelData === root.pending.res ? "check" : ""
                activeIcon: "aspect_ratio"
            }
        }

        Variants {
            id: rateItems

            model: root.rates

            MenuItem {
                required property string modelData

                text: `${parseFloat(modelData)} Hz`
                value: modelData
                icon: modelData === root.pending.rate ? "check" : ""
                activeIcon: "speed"
            }
        }

        Variants {
            id: placementItems

            model: root.placements

            MenuItem {
                required property var modelData

                text: modelData.text
                value: modelData
                activeIcon: "picture_in_picture"
            }
        }

        InfoRow {
            visible: !Hypr.usingLua
            first: true
            last: true
            icon: "warning"
            iconColour: Colours.palette.m3error
            label: Tr.tr("Requires a Lua Hyprland config")
            subtext: Tr.tr("This page applies and saves monitor rules through hl.monitor()")
        }

        // Confirm or revert
        ConnectedRect {
            Layout.fillWidth: true
            visible: root.revertRule !== null
            first: true
            last: true
            color: Colours.palette.m3secondaryContainer
            implicitHeight: confirmRow.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: confirmRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Keep these display settings? Reverting in %1 s").arg(root.countdown)
                    color: Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }

                ButtonRow {
                    spacing: Tokens.spacing.small

                    TextButton {
                        isRound: true
                        shapeMorph: true
                        horizontalPadding: Tokens.padding.large
                        verticalPadding: Tokens.padding.small
                        type: TextButton.Tonal
                        text: Tr.trCtx("Revert", "button")
                        onClicked: root.revert()
                    }

                    TextButton {
                        isRound: true
                        shapeMorph: true
                        horizontalPadding: Tokens.padding.large
                        verticalPadding: Tokens.padding.small
                        text: Tr.trCtx("Keep", "button")
                        onClicked: root.keep()
                    }
                }
            }
        }

        InfoRow {
            visible: root.error !== ""
            first: true
            last: true
            icon: "error"
            iconColour: Colours.palette.m3error
            label: Tr.tr("Hyprland rejected the change")
            subtext: root.error
        }

        InfoRow {
            visible: root.hdrRejected
            first: true
            last: true
            icon: "hdr_off"
            iconColour: Colours.palette.m3error
            label: Tr.tr("The monitor didn't switch to HDR")
            subtext: Tr.tr("It may not support HDR, or HDR is off in the monitor's own menu")
        }

        // Monitor
        SectionHeader {
            first: !(root.revertRule || root.error || root.hdrRejected || !Hypr.usingLua)
            text: Tr.tr("Monitor")
        }

        SelectRow {
            visible: root.multi
            first: true
            label: Tr.tr("Monitor")
            subtext: Tr.tr("Display to configure")
            menuItems: monitorItems.instances
            active: menuItems.find(i => i.text === root.mon?.name) ?? null
            fallbackIcon: "monitor"
            onSelected: item => root.selectedName = item.text
        }

        InfoRow {
            first: !root.multi
            icon: root.isPrimary && root.multi ? "star" : "monitor"
            label: root.mon ? `${root.mon.make} ${root.mon.model}`.trim() || root.mon.name : Tr.tr("No monitors found")
            subtext: root.mon ? (root.isPrimary && root.multi ? Tr.tr("%1 · Primary monitor").arg(root.mon.name) : root.mon.name) : ""
            value: root.mon && !root.mon.disabled ? `${root.mon.width} × ${root.mon.height} @ ${Math.round(root.mon.refreshRate)} Hz` : Tr.tr("Disabled")
        }

        ToggleRow {
            last: true
            text: Tr.tr("Enabled")
            subtext: root.pending.enabled && root.enabledCount <= 1 ? Tr.tr("The only active display can't be turned off") : Tr.tr("Turn this display on or off")
            disabled: (root.pending.enabled ?? false) && root.enabledCount <= 1
            checked: root.pending.enabled ?? true
            onToggled: root.set("enabled", checked)
        }

        // Picture
        SectionHeader {
            visible: root.pending.enabled ?? false
            text: Tr.tr("Picture")
        }

        SelectRow {
            visible: root.pending.enabled ?? false
            first: true
            label: Tr.tr("Resolution")
            menuItems: resItems.instances
            active: menuItems.find(i => i.value === root.pending.res) ?? null
            fallbackIcon: "aspect_ratio"
            fallbackText: root.pending.res ?? ""
            onSelected: item => root.set("res", item.value)
        }

        SelectRow {
            visible: root.pending.enabled ?? false
            label: Tr.tr("Refresh rate")
            menuItems: rateItems.instances
            active: menuItems.find(i => i.value === root.pending.rate) ?? null
            fallbackIcon: "speed"
            fallbackText: root.pending.rate ?? ""
            onSelected: item => root.set("rate", item.value)
        }

        StepperRow {
            visible: root.pending.enabled ?? false
            label: Tr.tr("Scale")
            subtext: Tr.tr("Hyprland picks the closest valid value")
            value: root.pending.scale ?? 1
            from: 0.5
            to: 4
            stepSize: 0.05
            onMoved: v => root.set("scale", v)
        }

        SelectRow {
            visible: root.pending.enabled ?? false
            label: Tr.tr("Rotation")
            menuItems: root.transformItems
            active: root.transformItems[root.pending.transform] ?? root.transformItems[0]
            onSelected: item => root.set("transform", root.transformItems.indexOf(item))
        }

        SelectRow {
            visible: root.pending.enabled ?? false
            last: true
            label: Tr.tr("Variable refresh rate")
            subtext: Tr.tr("Adaptive sync (FreeSync / G-Sync)")
            menuItems: root.vrrItems
            active: root.vrrItems[root.pending.vrr] ?? root.vrrItems[0]
            onSelected: item => root.set("vrr", root.vrrItems.indexOf(item))
        }

        // HDR
        SectionHeader {
            visible: root.pending.enabled ?? false
            text: "HDR"
        }

        ToggleRow {
            visible: root.pending.enabled ?? false
            first: true
            last: !root.pending.hdr
            text: "HDR"
            subtext: Tr.tr("Needs an HDR capable monitor, uses 10-bit colour")
            checked: root.pending.hdr ?? false
            onToggled: root.set("hdr", checked)
        }

        StepperRow {
            visible: (root.pending.enabled && root.pending.hdr) ?? false
            label: Tr.tr("SDR brightness")
            subtext: Tr.tr("Brightness of non-HDR content while HDR is on")
            value: root.pending.sdrBrightness ?? 1
            from: 0.5
            to: 3
            stepSize: 0.05
            onMoved: v => root.set("sdrBrightness", v)
        }

        StepperRow {
            visible: (root.pending.enabled && root.pending.hdr) ?? false
            last: true
            label: Tr.tr("SDR saturation")
            subtext: Tr.tr("Colour saturation of non-HDR content while HDR is on")
            value: root.pending.sdrSaturation ?? 1
            from: 0.5
            to: 2
            stepSize: 0.05
            onMoved: v => root.set("sdrSaturation", v)
        }

        // Multiple monitors
        SectionHeader {
            visible: root.multi
            text: Tr.tr("Multiple monitors")
        }

        SelectRow {
            visible: root.multi
            first: true
            last: root.isPrimary || !root.pending.enabled
            label: Tr.tr("Primary monitor")
            subtext: Tr.tr("Applied right away: cursor, workspace 1 and games (XWayland)")
            menuItems: primaryItems.instances
            active: menuItems.find(i => i.text === root.primaryName) ?? null
            fallbackIcon: "star"
            fallbackText: root.primaryName
            onSelected: item => root.setPrimary(item.text)
        }

        SelectRow {
            visible: root.multi && !root.isPrimary && (root.pending.enabled ?? false)
            last: !!root.pending.mirror
            label: Tr.tr("Mode")
            subtext: root.pending.mirror ? Tr.tr("Showing the same picture as %1").arg(root.pending.mirror) : Tr.tr("Separate desktop next to the primary monitor")
            menuItems: root.displayModeItems
            active: root.displayModeItems[root.pending.mirror ? 1 : 0]
            onSelected: item => root.set("mirror", root.displayModeItems.indexOf(item) === 1 ? root.primaryName : "")
        }

        SelectRow {
            visible: root.multi && !root.isPrimary && (root.pending.enabled ?? false) && !root.pending.mirror
            label: Tr.tr("Placement")
            subtext: Tr.tr("Where this monitor sits relative to the primary one")
            menuItems: placementItems.instances
            active: menuItems.find(i => i.value.x === root.pending.x && i.value.y === root.pending.y) ?? null
            fallbackIcon: "tune"
            fallbackText: Tr.trCtx("Custom", "monitor placement")
            onSelected: item => {
                root.set("x", item.value.x);
                root.set("y", item.value.y);
            }
        }

        StepperRow {
            visible: root.multi && (root.pending.enabled ?? false) && !root.pending.mirror && !root.isPrimary
            label: Tr.tr("Position X")
            subtext: Tr.tr("Horizontal offset in the layout (px)")
            value: root.pending.x ?? 0
            from: -20000
            to: 20000
            stepSize: 10
            onMoved: v => root.set("x", v)
        }

        StepperRow {
            visible: root.multi && (root.pending.enabled ?? false) && !root.pending.mirror && !root.isPrimary
            last: true
            label: Tr.tr("Position Y")
            subtext: Tr.tr("Vertical offset in the layout (px)")
            value: root.pending.y ?? 0
            from: -20000
            to: 20000
            stepSize: 10
            onMoved: v => root.set("y", v)
        }

        InfoRow {
            Layout.topMargin: Tokens.spacing.medium
            visible: !root.includedInConfig && Hypr.usingLua
            first: true
            last: true
            icon: "info"
            label: Tr.tr("Saved settings won't load on login")
            subtext: Tr.tr("Add pcall(require, \"hypr-monitors\") to hypr-user.lua")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            spacing: Tokens.spacing.small

            Item {
                Layout.fillWidth: true
            }

            ButtonRow {
                spacing: parent.spacing

                TextButton {
                    isRound: true
                    shapeMorph: true
                    horizontalPadding: Tokens.padding.extraLarge
                    verticalPadding: Tokens.padding.medium
                    type: TextButton.Tonal
                    text: Tr.trCtx("Reset", "button")
                    disabled: !root.dirty || root.revertRule !== null
                    onClicked: root.resetPending()
                }

                TextButton {
                    isRound: true
                    shapeMorph: true
                    horizontalPadding: Tokens.padding.extraLarge
                    verticalPadding: Tokens.padding.medium
                    text: Tr.trCtx("Apply", "button")
                    disabled: !root.dirty || root.revertRule !== null || !Hypr.usingLua
                    onClicked: root.apply()
                }
            }
        }
    }
}
