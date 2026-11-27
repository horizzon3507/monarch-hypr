import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ShellLogic.js" as Logic

// Quick toggles: the monarch-toggle-* switches from the terminal menu as a
// shell panel. Each row reads its state from the toggle's own `status`
// command ({"enabled":bool}); a click flips it with the bare command and the
// panel re-reads every row shortly after, so the switches show what the
// system reports, never what the click hoped for. Hardware-gated rows only
// appear when their probe says the hardware exists.
ColumnLayout {
    id: root
    spacing: 6

    // key -> true/false (read state) or null (unread/unreadable).
    property var states: ({})
    // probe key -> true/false; absent key means not read yet, row hidden.
    property var probeState: ({})
    // Bump to make every row re-run its status probe.
    property int probeGeneration: 0

    readonly property var rows: Logic.togglesAvailable(probeState)
    property int focusIndex: 0

    function scrollBy(delta) { focusIndex = Logic.moveFocus(focusIndex, delta, rows.length); }
    function activateFocused() { if (rows.length > 0) activate(rows[focusIndex].key); }

    function setState(key, value) {
        var next = Object.assign({}, root.states);
        next[key] = value;
        root.states = next;
    }

    function setProbe(key, value) {
        var next = Object.assign({}, root.probeState);
        next[key] = value;
        root.probeState = next;
    }

    function activate(key) {
        var action = Logic.toggleAction(key);
        if (action.length === 0) return;
        Quickshell.execDetached(action);
        // The toggle scripts are quick but detached; re-read after a beat so
        // the switches settle on the reported state.
        reprobeTimer.restart();
    }

    // Scripted control for tests and automation; same dispatch as clicks.
    IpcHandler {
        target: "toggles"
        function press(key: string): void { root.activate(key); }
        function state(key: string): string {
            var v = root.states[key];
            return v === true ? "on" : (v === false ? "off" : "unknown");
        }
    }

    Timer {
        id: reprobeTimer
        interval: 1000
        repeat: false
        onTriggered: root.probeGeneration += 1
    }

    // Hardware gates, probed once when the panel loads.
    Repeater {
        model: Logic.toggleProbes()
        delegate: Process {
            required property var modelData
            command: modelData.command
            Component.onCompleted: running = true
            onExited: function (exitCode) { root.setProbe(modelData.key, exitCode === 0); }
        }
    }

    Text {
        text: "Toggles"
        color: Theme.fg
        font.pixelSize: 16
        font.bold: true
        Layout.bottomMargin: 4
    }

    Repeater {
        model: root.rows
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            implicitWidth: 300
            implicitHeight: 40
            radius: 8
            color: Theme.surfaceVariant
            border.width: 2
            border.color: index === root.focusIndex ? Theme.accent : "transparent"

            property var state: root.states[modelData.key]

            Process {
                id: statusProc
                command: row.modelData.status
                stdout: StdioCollector { id: statusOut }
                onExited: function (exitCode) {
                    root.setState(row.modelData.key, Logic.parseToggleStatus(statusOut.text, exitCode));
                }
            }
            Component.onCompleted: statusProc.running = true
            Connections {
                target: root
                function onProbeGenerationChanged() { if (!statusProc.running) statusProc.running = true; }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.label
                color: Theme.fg
                font.pixelSize: 14
            }

            // Switch: a pill with a knob. On reads accent, off reads outline,
            // unknown keeps the off look (the row never claims a state it did
            // not read).
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 24
                radius: 12
                color: row.state === true ? Theme.accent : Theme.outline

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    y: 3
                    x: row.state === true ? parent.width - width - 3 : 3
                    color: Theme.bg
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.activate(row.modelData.key)
            }
        }
    }
}
