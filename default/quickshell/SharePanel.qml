import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ShellLogic.js" as Logic

// Share actions: the terminal share menu as a panel. Clipboard, file and
// folder shares hand off to the share helper (the file rows open a
// chooser), receive focuses LocalSend, and Wi-Fi QR switches to the QR
// panel. Every action dispatches detached; all but the panel switch close
// afterwards so the chooser or LocalSend owns the screen. Commands live in
// ShellLogic.
ColumnLayout {
    id: root
    spacing: 6

    readonly property var actions: Logic.shareActions()
    property int focusIndex: 0

    function scrollBy(delta) { focusIndex = Logic.moveFocus(focusIndex, delta, actions.length); }
    function activateFocused() { if (actions.length > 0) activate(actions[focusIndex].key); }

    function activate(key) {
        var command = Logic.shareCommand(key);
        if (command.length === 0) return;
        Quickshell.execDetached(command);
        if (Logic.shareCloses(key)) Quickshell.execDetached(["monarch-panel", "close"]);
    }

    // Scripted control for tests and automation; same dispatch as clicks.
    IpcHandler {
        target: "share"
        function press(key: string): void { root.activate(key); }
    }

    Text {
        text: "Share"
        color: Theme.fg
        font.pixelSize: 16
        font.bold: true
        Layout.bottomMargin: 4
    }

    Repeater {
        model: root.actions
        delegate: Rectangle {
            required property var modelData
            required property int index
            implicitWidth: 260
            implicitHeight: 34
            radius: 8
            color: Theme.surfaceVariant
            border.width: 2
            border.color: index === root.focusIndex ? Theme.accent : "transparent"
            Text {
                anchors.centerIn: parent
                text: modelData.label
                color: Theme.fg
                font.pixelSize: 14
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.activate(modelData.key)
            }
        }
    }
}
