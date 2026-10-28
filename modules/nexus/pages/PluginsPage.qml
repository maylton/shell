pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property string trackingUrl: "https://github.com/caelestia-dots/shell/issues/1384"
    readonly property bool localBuild: !Quickshell.shellDir.startsWith("/etc/") && !Quickshell.shellDir.startsWith("/usr/")

    property list<var> hyprPlugins: []
    property list<var> packages: []

    title: Tr.tr("Plugins")

    Component.onCompleted: ShellPlugins.refresh()

    // Installed Caelestia components, e.g. "caelestia-shell 2.5.0-1"
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            running: true
            command: ["hyprctl", "plugin", "list", "-j"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        root.hyprPlugins = JSON.parse(text);
                    } catch (e) {
                        root.hyprPlugins = [];
                    }
                }
            }
        }

        Process {
            running: true
            command: ["sh", "-c", "pacman -Q 2>/dev/null | grep -E '^caelestia'"]
            stdout: StdioCollector {
                onStreamFinished: root.packages = text.trim().split("\n").filter(l => l).map(l => {
                    const [name, version] = l.split(" ");
                    return {
                        name,
                        version
                    };
                })
            }
        }

        // Status
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: status.implicitHeight + Tokens.padding.extraLarge * 2

            ColumnLayout {
                id: status

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "extension"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.extraLarge
                    fill: 1
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Tr.tr("Official plugin support is coming")
                    font: Tokens.font.title.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Tr.tr("Caelestia doesn't have an official plugin system yet. Local extensions installed on this system are managed below.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }

                TextButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.spacing.small
                    isRound: true
                    shapeMorph: true
                    horizontalPadding: Tokens.padding.extraLarge
                    verticalPadding: Tokens.padding.medium
                    type: TextButton.Tonal
                    text: Tr.trCtx("Follow progress on GitHub", "button")
                    onClicked: Qt.openUrlExternally(root.trackingUrl)
                }
            }
        }

        // Local extensions, toggled through their systemd user services
        SectionHeader {
            text: Tr.tr("Shell plugins")
        }

        InfoRow {
            visible: ShellPlugins.installed.length === 0
            first: true
            last: true
            icon: "extension_off"
            label: Tr.tr("No shell plugins installed")
        }

        Repeater {
            model: ShellPlugins.installed

            ColumnLayout {
                id: plugin

                required property var modelData
                required property int index

                readonly property bool active: ShellPlugins.isActive(modelData)

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                ToggleRow {
                    first: true
                    last: !plugin.active || !plugin.modelData.app
                    text: plugin.modelData.name
                    subtext: {
                        const state = plugin.active ? Tr.trCtx("Running", "plugin state") : Tr.trCtx("Stopped", "plugin state");
                        return `${state} · ${plugin.modelData.description}`;
                    }
                    checked: ShellPlugins.isEnabled(plugin.modelData)
                    onToggled: ShellPlugins.setEnabled(plugin.modelData, checked)
                }

                RowButton {
                    visible: plugin.active && plugin.modelData.app
                    last: true
                    icon: plugin.modelData.icon
                    text: Tr.tr("Open %1").arg(plugin.modelData.name)
                    trailingIcon: "open_in_new"
                    onClicked: Quickshell.execDetached([plugin.modelData.app])
                }
            }
        }

        // Hyprland plugins
        SectionHeader {
            text: Tr.tr("Hyprland plugins")
        }

        InfoRow {
            visible: root.hyprPlugins.length === 0
            first: true
            last: true
            icon: "extension_off"
            label: Tr.tr("No Hyprland plugins loaded")
        }

        Repeater {
            model: root.hyprPlugins

            InfoRow {
                required property var modelData
                required property int index

                first: index === 0
                last: index === root.hyprPlugins.length - 1
                icon: "extension"
                label: modelData.name ?? ""
                subtext: [modelData.author, modelData.description].filter(s => s).join(" · ")
                value: modelData.version ?? ""
            }
        }

        // Caelestia components
        SectionHeader {
            text: Tr.tr("Caelestia components")
        }

        InfoRow {
            first: true
            last: root.packages.length === 0
            icon: "terminal"
            label: Tr.tr("Running shell")
            subtext: root.localBuild ? Tr.tr("Local build: %1").arg(Quickshell.shellDir) : Quickshell.shellDir
            value: CUtils.version || "…"
        }

        Repeater {
            model: root.packages

            InfoRow {
                required property var modelData
                required property int index

                last: index === root.packages.length - 1
                icon: "package_2"
                label: modelData.name
                value: modelData.version
            }
        }
    }
}
