pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "ShellLogic.js" as Logic

// Shell settings from ~/.config/monarch/shell.json. Monarch commands write the
// file; this singleton only reads it and reloads when it changes.
Singleton {
    id: root

    readonly property string path: Quickshell.env("MONARCH_SHELL_SETTINGS")
        || (Quickshell.env("HOME") + "/.config/monarch/shell.json")

    property var values: Logic.normalize(null)
    readonly property bool barVisible: values.barVisible
    readonly property string barPosition: values.barPosition
    readonly property bool batteryPercent: values.batteryPercent
    readonly property real textScale: values.textScale

    FileView {
        path: root.path
        watchChanges: true
        printErrors: false
        onLoaded: root.values = Logic.parse(text())
        onLoadFailed: root.values = Logic.normalize(null)
        onFileChanged: reload()
    }
}
