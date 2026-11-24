import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "ShellLogic.js" as Logic

// Per-screen scale and brightness, and the global text size, through the
// existing Monarch commands (monarch-display-list, -scale, -brightness and
// -text-size). Changing a scale reloads Hyprland, so it is gated like every
// other change: one gate, nothing runs while a read or change is in flight.
ColumnLayout {
    id: root
    spacing: 8

    property var displays: null          // null: not read or unreadable
    property var brightness: ({})
    property int textSize: 0             // 0: unknown
    property bool loading: true
    property string busy: ""
    property string errorText: ""      // a real failure; stays until the next action
    property string busyNotice: ""     // "busy" hint; goes away once things settle

    readonly property bool settled: !listProc.running && !briProc.running && !textProc.running && busy === ""

    function refresh() {
        if (listProc.running || briProc.running || textProc.running || busy !== "") return;
        loading = true;
        listProc.running = true;
        briProc.running = true;
        textProc.running = true;
    }

    // The one gate every state-changing entry point goes through.
    function mayMutate() {
        if (!settled) { busyNotice = "Busy, try again in a moment"; return false; }
        return true;
    }

    function act(kind, command) {
        if (!mayMutate()) return;
        busy = kind; errorText = ""; busyNotice = "";
        action.kind = kind;
        action.command = command;
        action.running = true;
    }

    function stepScale(name, current, direction) {
        var next = Logic.stepScale(current, direction);
        if (next > 0) act("scale", ["monarch-display-scale", name, String(next)]);
    }

    function stepBrightness(name, percent, direction) {
        var next = Logic.stepBrightness(percent, direction);
        if (next >= 0) act("brightness", ["monarch-display-brightness", name, String(next)]);
    }

    function stepText(direction) {
        var next = Logic.stepTextSize(textSize, direction);
        if (next > 0) act("text size", ["monarch-display-text-size", String(next)]);
    }

    Component.onCompleted: refresh()

    Process {
        id: listProc
        command: ["monarch-display-list"]
        stdout: StdioCollector { id: listOut }
        stderr: StdioCollector { id: listErr }
        onExited: function (exitCode) {
            root.loading = false;
            var parsed = exitCode === 0 ? Logic.parseDisplayList(listOut.text) : null;
            if (parsed !== null) { root.displays = parsed; root.busyNotice = ""; return; }
            // An unreadable list is unavailable, never "no displays".
            root.displays = null;
            var message = listErr.text.trim();
            root.errorText = message !== "" ? message : "Could not read the displays";
        }
    }

    Process {
        id: briProc
        command: ["monarch-display-brightness", "--list"]
        stdout: StdioCollector { id: briOut }
        onExited: function (exitCode) { root.brightness = exitCode === 0 ? Logic.parseBrightnessList(briOut.text) : ({}); }
    }

    Process {
        id: textProc
        command: ["monarch-display-text-size", "--current"]
        stdout: StdioCollector { id: textOut }
        onExited: function (exitCode) { root.textSize = exitCode === 0 ? Logic.parseTextSize(textOut.text) : 0; }
    }

    Process {
        id: action
        property string kind: ""
        stderr: StdioCollector { id: actionErr }
        onExited: function (exitCode) {
            root.busy = "";
            root.busyNotice = "";
            if (exitCode !== 0) {
                var message = actionErr.text.trim();
                root.errorText = message !== "" ? message : "Could not change the " + action.kind;
            }
            root.refresh();
        }
    }

    Text {
        text: "Displays"
        color: Theme.fg
        font.pixelSize: 16
        font.bold: true
        Layout.preferredWidth: 340
        // Keep the header clear of the host's close button in the card corner.
        Layout.rightMargin: 24
    }

    Text {
        visible: root.errorText !== "" || root.busyNotice !== ""
        text: root.busyNotice !== "" ? root.busyNotice : root.errorText
        color: Theme.error
        wrapMode: Text.Wrap
        Layout.preferredWidth: 340
    }

    Repeater {
        model: root.displays !== null ? root.displays : []

        delegate: ColumnLayout {
            id: screen
            required property var modelData
            readonly property var bri: root.brightness[modelData.name]
            spacing: 4
            Layout.preferredWidth: 340
            Layout.alignment: Qt.AlignLeft
            opacity: root.settled ? 1.0 : 0.6

            Text {
                text: screen.modelData.name + (screen.modelData.enabled ? "  " + screen.modelData.mode : "  off")
                color: Theme.fg
                font.pixelSize: 14
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            StepRow {
                visible: screen.modelData.enabled
                label: "Scale"
                valueText: screen.modelData.scale + "x"
                onStepped: function (direction) { root.stepScale(screen.modelData.name, screen.modelData.scale, direction); }
            }

            StepRow {
                visible: screen.modelData.enabled && screen.bri !== undefined
                label: "Brightness"
                valueText: screen.bri !== undefined ? screen.bri.percent + "%" : ""
                onStepped: function (direction) { root.stepBrightness(screen.modelData.name, screen.bri.percent, direction); }
            }
        }
    }

    StepRow {
        visible: root.displays !== null
        label: "Text size"
        valueText: root.textSize > 0 ? root.textSize + "%" : "unknown"
        active: root.textSize > 0
        onStepped: function (direction) { root.stepText(direction); }
    }

    Text {
        visible: root.loading && root.displays === null
        text: "Loading..."
        color: Theme.fg
        opacity: 0.6
    }
}
