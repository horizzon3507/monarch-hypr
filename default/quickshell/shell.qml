//@ pragma UseQApplication
import QtQuick
import Quickshell

// Monarch shell entry point. Surfaces (bar, panels) attach here as they land.
ShellRoot {
    Component.onCompleted: console.log("monarch-shell started, bar position " + Settings.barPosition)
}
