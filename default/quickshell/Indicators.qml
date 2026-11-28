import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell
import Quickshell.Io
import "ShellLogic.js" as Logic

// Battery, volume and internal-backlight readouts. Each hides itself when its
// source has nothing to show (no battery, no default sink, no backlight).
RowLayout {
    id: root
    spacing: 12
    property int fontSize: 13
    // Compact mode (narrow bars): vol/brightness readouts hide, state chips
    // (including the privacy-sensitive recording chip) and battery stay.
    property bool compact: false

    // Widths for the bar's adaptive budget, computed only from parts whose
    // visibility does not depend on `compact`, so the bar's level decision
    // stays free of binding loops.
    readonly property bool hasBri: Logic.brightnessText(root.brightness) !== ""
    readonly property bool hasVol: Pipewire.defaultAudioSink !== null
        && Pipewire.defaultAudioSink.audio !== null
    readonly property bool hasBat: UPower.displayDevice !== null
        && UPower.displayDevice.isPresent && UPower.displayDevice.isLaptopBattery
    function chipsWidth() {
        var w = 0;
        for (var i = 0; i < chipsRepeater.count; i++) {
            var it = chipsRepeater.itemAt(i);
            if (it !== null) w += it.implicitWidth;
        }
        if (chipsRepeater.count > 1) w += (chipsRepeater.count - 1) * spacing;
        return w;
    }
    function rowWidth(parts) {
        var w = 0, n = 0;
        for (var i = 0; i < parts.length; i++)
            if (parts[i] > 0) { w += parts[i]; n++; }
        return n === 0 ? 0 : w + (n - 1) * spacing;
    }
    readonly property int fullWidth: rowWidth([chipsWidth(),
        hasBri ? briText.width : 0, hasVol ? volText.width : 0, hasBat ? batText.width : 0])
    readonly property int compactWidth: rowWidth([chipsWidth(), hasBat ? batText.width : 0])

    // Backlight percent from `monarch-display-brightness --list`, polled while the
    // bar is up. Nothing shows without an internal backlight (desktop, external
    // monitor only, command failing), so a failed read is not shown as a value.
    property var brightness: ({})
    Process {
        id: briProc
        command: ["monarch-display-brightness", "--list"]
        stdout: StdioCollector { id: briOut }
        onExited: function (exitCode) { root.brightness = exitCode === 0 ? Logic.parseBrightnessList(briOut.text) : ({}); }
    }
    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!briProc.running) briProc.running = true
    }

    // State chips: recording, caffeine, do-not-disturb, night light and pending
    // updates. A chip shows only for a state read as on; an unreadable state
    // shows nothing and is never taken as off (see ShellLogic.stateChips). A
    // click runs the chip's own command.
    property var chipState: ({ recording: null, caffeine: null, dnd: null, nightlight: null, update: null })
    property bool updateFailed: false

    function setChip(key, value) {
        if (root.chipState[key] !== value) console.log("TRAYPOPDIAG chipstate " + key + ": " + root.chipState[key] + " -> " + value);
        var next = Object.assign({}, root.chipState);
        next[key] = value;
        root.chipState = next;
    }

    // Recording is the privacy chip, so it is read on its own short cycle.
    Process {
        id: recProc
        command: ["monarch-capture-screenrecording", "--status"]
        onExited: function (exitCode) { root.setChip("recording", Logic.parseRecordingStatus(exitCode)); }
    }
    Process {
        id: idleProc
        command: ["monarch-toggle-idle", "status"]
        stdout: StdioCollector { id: idleOut }
        onExited: function (exitCode) { root.setChip("caffeine", Logic.parseToggleStatus(idleOut.text, exitCode)); }
    }
    Process {
        id: dndProc
        command: ["monarch-toggle-notification-silencing", "status"]
        stdout: StdioCollector { id: dndOut }
        onExited: function (exitCode) { root.setChip("dnd", Logic.parseToggleStatus(dndOut.text, exitCode)); }
    }
    Process {
        id: nightProc
        command: ["monarch-toggle-nightlight", "status"]
        stdout: StdioCollector { id: nightOut }
        onExited: function (exitCode) { root.setChip("nightlight", Logic.parseToggleStatus(nightOut.text, exitCode)); }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!recProc.running) recProc.running = true;
            if (!idleProc.running) idleProc.running = true;
            if (!dndProc.running) dndProc.running = true;
            if (!nightProc.running) nightProc.running = true;
        }
    }

    // The update check syncs a temporary package database, so it runs rarely:
    // after a short delay at start, then every 6 h while current, every 10 min
    // while updates are pending or the check failed. It is not run while the
    // network is known to be offline (the gate is re-read every minute); a known
    // count stays, marked stale.
    Process {
        id: netProc
        command: ["nmcli", "-t", "-f", "STATE,CONNECTIVITY", "general"]
        stdout: StdioCollector { id: netOut }
        onExited: function (exitCode) {
            if (Logic.parseNetworkState(netOut.text, exitCode) === "offline") {
                root.setChip("update", Logic.updateOfflineState(root.chipState.update));
                updateTimer.interval = 60000;
                updateTimer.restart();
            } else if (!updateProc.running) {
                updateProc.running = true;
            }
        }
    }
    Process {
        id: updateProc
        command: ["monarch-update-available", "--all", "--json"]
        stdout: StdioCollector { id: updateOut }
        onExited: function (exitCode) {
            var check = Logic.parseUpdateCheck(updateOut.text, exitCode);
            root.updateFailed = check.status === "error";
            root.setChip("update", Logic.updateChipState(root.chipState.update, updateOut.text, exitCode));
            updateTimer.interval = Logic.updateIntervalMinutes(root.chipState.update, root.updateFailed) * 60000;
            updateTimer.restart();
        }
    }
    Timer {
        id: updateTimer
        interval: 90000
        running: true
        onTriggered: if (!netProc.running && !updateProc.running) netProc.running = true
    }

    Repeater {
        id: chipsRepeater
        model: Logic.stateChips(root.chipState)
        Text {
            required property var modelData
            text: modelData.text
            font.pixelSize: root.fontSize
            font.bold: modelData.urgent
            color: modelData.urgent ? Theme.error : Theme.fg
            opacity: modelData.urgent ? 1.0 : (modelData.dim ? 0.5 : 0.8)
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(modelData.action)
            }
        }
    }

    Text {
        id: briText
        visible: !root.compact && text !== ""
        text: Logic.brightnessText(root.brightness)
        font.pixelSize: root.fontSize
        color: Theme.fg
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Text {
        id: volText
        readonly property var sink: Pipewire.defaultAudioSink
        visible: !root.compact && sink !== null && sink.audio !== null
        text: visible ? "vol " + Logic.volumeText(sink.audio.volume, sink.audio.muted) : ""
        font.pixelSize: root.fontSize
        color: Theme.fg
        opacity: visible && sink.audio.muted ? 0.6 : 1.0
    }

    Text {
        id: batText
        readonly property var battery: UPower.displayDevice
        readonly property bool charging: battery !== null
            && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged)
        visible: battery !== null && battery.isPresent && battery.isLaptopBattery
        text: visible ? "bat " + Logic.batteryPercent(battery.percentage) + "%" + (charging ? " +" : "") : ""
        font.pixelSize: root.fontSize
        color: visible && !charging && Logic.batteryPercent(battery.percentage) <= 15 ? Theme.error : Theme.fg
    }
}
