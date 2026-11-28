import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ShellLogic.js" as Logic

// Capture actions: screenshots, text/QR/color tools and screen recording.
// One-shot captures dispatch detached and the panel closes so the interactive
// capture is not covered. An active recording replaces the record variants
// with a stop row, like the terminal capture menu.
ColumnLayout {
    id: root
    spacing: 6

    property bool recording: false
    property bool hasWebcam: false

    readonly property var actions: Logic.captureActions()
    readonly property var recordActions: Logic.captureRecordActions(hasWebcam)
    // One list for clicks and keyboard focus: an active recording replaces
    // the record variants with the stop row, like the terminal capture menu.
    readonly property var rows: root.actions.concat(root.recording ? [{ key: "stop", label: "Stop recording" }] : root.recordActions)
    property int focusIndex: 0

    function scrollBy(delta) { focusIndex = Logic.moveFocus(focusIndex, delta, rows.length); }
    function activateFocused() { if (rows.length > 0) activate(rows[focusIndex].key); }

    // Dispatch, then close so the capture UI owns the screen.
    function activate(key) {
        var command = Logic.captureCommand(key);
        if (command.length === 0) return;
        Quickshell.execDetached(command);
        Quickshell.execDetached(["monarch-panel", "close"]);
    }

    // Scripted control for tests and automation; same dispatch as clicks.
    IpcHandler {
        target: "capture"
        function press(key: string): void { root.activate(key); }
        function recording(): bool { return root.recording; }
    }

    Process {
        id: recordProbe
        command: ["pgrep", "-f", "^gpu-screen-recorder"]
        onExited: function (exitCode) { root.recording = exitCode === 0 }
    }

    Process {
        id: webcamProbe
        command: ["monarch-hw-webcam"]
        onExited: function (exitCode) { root.hasWebcam = exitCode === 0 }
    }

    Component.onCompleted: {
        recordProbe.running = true;
        webcamProbe.running = true;
    }

    Text {
        text: "Capture"
        color: Theme.fg
        font.pixelSize: 16
        font.bold: true
        Layout.bottomMargin: 4
    }

    Repeater {
        model: root.rows
        delegate: Rectangle {
            required property var modelData
            required property int index
            implicitWidth: 260
            implicitHeight: 34
            radius: 8
            color: modelData.key === "stop" ? Theme.error : Theme.surfaceVariant
            border.width: 2
            border.color: index === root.focusIndex ? Theme.accent : "transparent"
            Text {
                anchors.centerIn: parent
                text: modelData.label
                color: modelData.key === "stop" ? Theme.bg : Theme.fg
                font.pixelSize: 14
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.activate(modelData.key)
            }
        }
    }
}
