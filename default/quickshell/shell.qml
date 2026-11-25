//@ pragma UseQApplication
import QtQuick
import Quickshell

// Monarch shell entry point. The bar and the panel host attach here.
ShellRoot {
    Component.onCompleted: console.log("monarch-shell started")

    Wallpaper {}
    Bar {}
    PanelHost {}

    // Log applied state after FileView has loaded (and again on every reload),
    // so tests observe the real values rather than the startup defaults.
    Connections {
        target: Settings
        function onValuesChanged() {
            console.log("monarch-shell settings barPosition=" + Settings.barPosition
                + " barVisible=" + Settings.barVisible
                + " batteryPercent=" + Settings.batteryPercent
                + " textScale=" + Settings.textScale)
        }
    }
    Connections {
        target: Theme
        function onPaletteChanged() { console.log("monarch-shell theme accent=" + Theme.accent) }
    }
}
