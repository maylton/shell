pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n

// Local shell extensions that run as systemd user services, toggled from Nexus → Plugins.
// Stand-in until upstream has a real plugin system.
Singleton {
    id: root

    readonly property list<var> plugins: [
        {
            id: "caelestia-connect",
            name: "Caelestia Connect",
            description: Tr.tr("Phone integration (KDE Connect compatible)"),
            icon: "smartphone",
            service: "caelestia-connectd.service",
            app: `${Quickshell.env("HOME")}/.local/bin/caelestia-connect`
        }
    ]

    // service name -> { installed, enabled, active }
    property var states: ({})
    readonly property list<var> installed: plugins.filter(p => states[p.service]?.installed)
    readonly property int activeCount: plugins.filter(p => states[p.service]?.active).length

    function isEnabled(plugin: var): bool {
        return states[plugin.service]?.enabled ?? false;
    }

    function isActive(plugin: var): bool {
        return states[plugin.service]?.active ?? false;
    }

    function setEnabled(plugin: var, enabled: bool): void {
        toggleProc.exec(["systemctl", "--user", enabled ? "enable" : "disable", "--now", plugin.service]);
    }

    function refresh(): void {
        stateProc.running = true;
    }

    Component.onCompleted: refresh()

    // Prints "<service> <is-enabled> <is-active>" per plugin
    Process {
        id: stateProc

        command: ["sh", "-c", `for s in ${root.plugins.map(p => p.service).join(" ")}; do echo "$s $(systemctl --user is-enabled $s 2>/dev/null) $(systemctl --user is-active $s 2>/dev/null)"; done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const states = {};
                for (const line of text.trim().split("\n")) {
                    const [service, enabled, active] = line.split(" ");
                    states[service] = {
                        installed: enabled !== "not-found" && enabled !== "",
                        enabled: enabled === "enabled",
                        active: active === "active"
                    };
                }
                root.states = states;
            }
        }
    }

    Process {
        id: toggleProc

        onExited: root.refresh()
    }
}
