pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property string script: `${Quickshell.shellDir}/assets/check_updates.sh`

    property list<var> repoUpdates: []
    property list<var> aurUpdates: []
    property list<var> flatpakUpdates: []
    property bool repoFailed
    property bool hasAurHelper
    property bool hasFlatpak
    property string aurHelper
    property date lastChecked

    readonly property bool checking: repoProc.running || aurProc.running || flatpakProc.running
    readonly property int total: repoUpdates.length + aurUpdates.length + flatpakUpdates.length

    function parsePkgLines(text: string): list<var> {
        return text.split("\n").map(l => l.match(/^(\S+)\s+(\S+)\s+->\s+(\S+)/)).filter(m => m).map(m => ({
                    name: m[1],
                    from: m[2],
                    to: m[3]
                }));
    }

    function check(): void {
        repoProc.running = true;
        if (hasAurHelper)
            aurProc.running = true;
        if (hasFlatpak)
            flatpakProc.running = true;
    }

    // Runs the full upgrade interactively in the configured terminal
    function updateAll(): void {
        const steps = [];
        if (aurHelper)
            steps.push(`${aurHelper} -Syu`);
        else
            steps.push("sudo pacman -Syu");
        if (hasFlatpak)
            steps.push("flatpak update");

        const script = `${steps.join(" && ")}; echo; printf '%s' 'Press Enter to close'; read _`;
        root.runInTerminal(["sh", "-c", script]);
    }

    function runInTerminal(cmd: list<string>): void {
        const term = GlobalConfig.general.apps.terminal;
        // These terminals need -e before the command, the rest take it directly
        const needsE = ["ghostty", "alacritty", "xterm", "konsole", "xfce4-terminal"].includes(term[0]?.split("/").pop());
        Quickshell.execDetached([...term, ...(needsE ? ["-e"] : []), ...cmd]);
    }

    title: Tr.tr("Updates")

    Component.onCompleted: toolsProc.running = true

    // Detect optional update sources before the first check
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            id: toolsProc

            command: ["sh", "-c", "for t in paru yay flatpak; do command -v $t > /dev/null && echo $t; done"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const tools = text.trim().split("\n");
                    root.aurHelper = tools.find(t => t === "paru" || t === "yay") ?? "";
                    root.hasAurHelper = root.aurHelper !== "";
                    root.hasFlatpak = tools.includes("flatpak");
                    root.check();
                }
            }
        }

        Process {
            id: repoProc

            command: [root.script, "repo"]
            stdout: StdioCollector {
                onStreamFinished: root.repoUpdates = root.parsePkgLines(text)
            }
            onExited: code => {
                root.repoFailed = code !== 0;
                root.lastChecked = new Date();
            }
        }

        Process {
            id: aurProc

            command: [root.script, "aur"]
            stdout: StdioCollector {
                onStreamFinished: root.aurUpdates = root.parsePkgLines(text)
            }
        }

        Process {
            id: flatpakProc

            command: [root.script, "flatpak"]
            stdout: StdioCollector {
                onStreamFinished: root.flatpakUpdates = text.split("\n").filter(l => l.trim()).map(l => {
                    const [name, version] = l.split("\t");
                    return {
                        name,
                        from: "",
                        to: version ?? ""
                    };
                })
            }
        }

        // Summary
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: summary.implicitHeight + Tokens.padding.extraLarge * 2

            ColumnLayout {
                id: summary

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.checking ? "sync" : root.total > 0 ? "system_update" : root.repoFailed ? "sync_problem" : "check_circle"
                    color: root.total > 0 ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.extraLarge
                    fill: 1
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        if (root.checking)
                            return Tr.tr("Checking for updates…");
                        if (root.total > 0)
                            return Tr.trN("%n update available", "%n updates available", root.total);
                        if (root.repoFailed)
                            return Tr.tr("Unable to check for updates");
                        return Tr.tr("System is up to date");
                    }
                    font: Tokens.font.title.medium
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !isNaN(root.lastChecked)
                    text: Tr.tr("Last checked at %1").arg(Qt.formatTime(root.lastChecked, Qt.locale().timeFormat(Locale.ShortFormat)))
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.medium
                }

                ButtonRow {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.spacing.small
                    spacing: Tokens.spacing.small

                    TextButton {
                        isRound: true
                        shapeMorph: true
                        horizontalPadding: Tokens.padding.extraLarge
                        verticalPadding: Tokens.padding.medium
                        type: TextButton.Tonal
                        text: Tr.trCtx("Check now", "button")
                        disabled: root.checking
                        onClicked: root.check()
                    }

                    TextButton {
                        isRound: true
                        shapeMorph: true
                        horizontalPadding: Tokens.padding.extraLarge
                        verticalPadding: Tokens.padding.medium
                        text: Tr.trCtx("Update all", "button")
                        disabled: root.checking || root.total === 0
                        onClicked: root.updateAll()
                    }
                }
            }
        }

        UpdateList {
            title: Tr.tr("Official repositories")
            updates: root.repoUpdates
        }

        UpdateList {
            visible: root.hasAurHelper
            title: "AUR"
            updates: root.aurUpdates
        }

        UpdateList {
            visible: root.hasFlatpak
            title: "Flatpak"
            updates: root.flatpakUpdates
        }

        // Caelestia
        SectionHeader {
            text: "Caelestia"
        }

        RowButton {
            first: true
            last: true
            icon: "auto_awesome"
            text: Tr.tr("Update Caelestia dotfiles")
            subtext: Tr.tr("Runs caelestia update in a terminal (also upgrades the system)")
            trailingIcon: "open_in_new"
            onClicked: root.runInTerminal(["sh", "-c", "caelestia update; echo; printf '%s' 'Press Enter to close'; read _"])
        }
    }

    component UpdateList: ColumnLayout {
        id: list

        property string title
        property list<var> updates

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            text: list.updates.length > 0 ? `${list.title} (${list.updates.length})` : list.title
        }

        InfoRow {
            visible: list.updates.length === 0
            first: true
            last: true
            icon: "done"
            label: root.checking ? Tr.tr("Checking…") : Tr.tr("No pending updates")
        }

        Repeater {
            model: list.updates

            InfoRow {
                required property var modelData
                required property int index

                first: index === 0
                last: index === list.updates.length - 1
                label: modelData.name
                subtext: modelData.from
                value: modelData.to
            }
        }
    }
}
