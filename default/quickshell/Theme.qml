pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "ShellLogic.js" as Logic

// Colors from ~/.config/monarch/current/theme/quickshell.json, rendered by
// monarch-theme-render from the active palette. Missing keys use defaults.
Singleton {
    id: root

    readonly property string path: Quickshell.env("MONARCH_SHELL_COLORS")
        || (Quickshell.env("HOME") + "/.config/monarch/current/theme/quickshell.json")

    property var palette: Logic.colors(null)
    readonly property color bg: palette.bg
    readonly property color fg: palette.fg
    readonly property color accent: palette.accent
    readonly property color outline: palette.outline
    readonly property color surfaceVariant: palette.surfaceVariant
    readonly property color error: palette.error
    readonly property color secondary: palette.secondary

    FileView {
        path: root.path
        watchChanges: true
        printErrors: false
        onLoaded: root.palette = Logic.parseColors(text())
        onLoadFailed: root.palette = Logic.colors(null)
        onFileChanged: reload()
    }
}
