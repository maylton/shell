pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // [{ name, flavour, colours }] from `caelestia scheme list`, excluding the dynamic scheme
    property var schemes: []
    readonly property bool isDynamic: Colours.scheme === "dynamic"

    readonly property var schemeNames: ({
            darkgreen: "Dark Green",
            oldworld: "Old World",
            onedark: "One Dark",
            rosepine: "Rosé Pine",
            shadotheme: "Shado",
            tokyonight: "Tokyo Night"
        })

    readonly property list<MenuItem> variantItems: [
        MenuItem {
            text: Tr.trCtx("Tonal Spot", "M3 scheme variant name")
            value: "tonalspot"
        },
        MenuItem {
            text: Tr.trCtx("Vibrant", "M3 scheme variant name")
            value: "vibrant"
        },
        MenuItem {
            text: Tr.trCtx("Expressive", "M3 scheme variant name")
            value: "expressive"
        },
        MenuItem {
            text: Tr.trCtx("Fidelity", "M3 scheme variant name")
            value: "fidelity"
        },
        MenuItem {
            text: Tr.trCtx("Content", "M3 scheme variant name")
            value: "content"
        },
        MenuItem {
            text: Tr.trCtx("Fruit Salad", "M3 scheme variant name")
            value: "fruitsalad"
        },
        MenuItem {
            text: Tr.trCtx("Rainbow", "M3 scheme variant name")
            value: "rainbow"
        },
        MenuItem {
            text: Tr.trCtx("Neutral", "M3 scheme variant name")
            value: "neutral"
        },
        MenuItem {
            text: Tr.trCtx("Monochrome", "M3 scheme variant name")
            value: "monochrome"
        }
    ]

    readonly property list<MenuItem> contrastItems: [
        MenuItem {
            text: Tr.tr("Default")
            value: "default"
        },
        MenuItem {
            text: Tr.tr("High")
            value: "hard"
        }
    ]

    function capitalise(s: string): string {
        return s.slice(0, 1).toUpperCase() + s.slice(1);
    }

    function setScheme(args: var): void {
        Quickshell.execDetached(["caelestia", "scheme", "set", "--notify", ...args]);
    }

    title: Tr.tr("Colours")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Scheme previews depend on the mode, so refresh them when it changes
        Connections {
            function onCurrentLightChanged(): void {
                getSchemes.running = true;
            }

            target: Colours
        }

        Process {
            id: getSchemes

            running: true
            command: ["caelestia", "scheme", "list"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const flat = [];
                    for (const [name, flavours] of Object.entries(JSON.parse(text)))
                        if (name !== "dynamic")
                            for (const [flavour, colours] of Object.entries(flavours))
                                flat.push({
                                    name,
                                    flavour,
                                    colours
                                });
                    root.schemes = flat.sort((a, b) => (a.name + a.flavour).localeCompare(b.name + b.flavour));
                }
            }
        }

        // Dynamic
        SectionHeader {
            first: true
            text: Tr.tr("Wallpaper colours")
        }

        RowButton {
            first: true
            icon: "wallpaper"
            text: Tr.tr("Use wallpaper colours")
            subtext: Tr.tr("Generate a palette from the current wallpaper")
            trailingIcon: root.isDynamic ? "check" : ""
            onClicked: root.setScheme(["-n", "dynamic"])
        }

        SelectRow {
            enabled: root.isDynamic
            opacity: enabled ? 1 : 0.5
            label: Tr.tr("Style")
            subtext: Tr.tr("How the palette is derived from the wallpaper")
            menuItems: root.variantItems
            active: root.variantItems.find(i => i.value === Colours.variant) ?? root.variantItems[0]
            onSelected: item => root.setScheme(["-v", item.value])
        }

        SelectRow {
            enabled: root.isDynamic
            opacity: enabled ? 1 : 0.5
            last: true
            label: Tr.tr("Contrast")
            menuItems: root.contrastItems
            active: root.contrastItems.find(i => root.isDynamic && i.value === Colours.flavour) ?? root.contrastItems[0]
            onSelected: item => root.setScheme(["-n", "dynamic", "-f", item.value])
        }

        // Presets
        SectionHeader {
            text: Tr.tr("Presets")
        }

        GridLayout {
            Layout.fillWidth: true

            columns: Math.max(2, Math.floor(width / 150))
            rowSpacing: Tokens.spacing.small
            columnSpacing: Tokens.spacing.small

            Repeater {
                model: root.schemes

                SchemeCard {}
            }
        }
    }

    component SchemeCard: StyledRect {
        id: card

        required property var modelData
        readonly property bool isCurrent: modelData.name === Colours.scheme && modelData.flavour === Colours.flavour

        Layout.fillWidth: true
        implicitHeight: cardLayout.implicitHeight + Tokens.padding.medium * 2

        radius: Tokens.rounding.large
        color: isCurrent ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer

        StateLayer {
            radius: card.radius
            onClicked: root.setScheme(["-n", card.modelData.name, "-f", card.modelData.flavour])
        }

        ColumnLayout {
            id: cardLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: swatches.implicitHeight + Tokens.padding.medium * 2

                radius: Tokens.rounding.medium
                color: `#${card.modelData.colours.surface}`
                border.width: 1
                border.color: Qt.alpha(`#${card.modelData.colours.outline}`, 0.5)

                Row {
                    id: swatches

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: ["primary", "secondary", "tertiary"]

                        StyledRect {
                            required property string modelData

                            implicitWidth: 20
                            implicitHeight: 20
                            radius: Tokens.rounding.full
                            color: `#${card.modelData.colours[modelData]}`
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.small
                spacing: Tokens.spacing.small

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.schemeNames[card.modelData.name] ?? root.capitalise(card.modelData.name)
                        color: card.isCurrent ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        font: Tokens.font.body.medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.capitalise(card.modelData.flavour)
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }

                MaterialIcon {
                    visible: card.isCurrent
                    text: "check_circle"
                    color: Colours.palette.m3onSecondaryContainer
                    fill: 1
                }
            }
        }
    }
}
