import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Io
import "ShellLogic.js" as Logic

// Battery, volume and internal-backlight readouts. Each hides itself when its
// source has nothing to show (no battery, no default sink, no backlight).
RowLayout {
    id: root
    spacing: 12
    property int fontSize: 13

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

    Text {
        visible: text !== ""
        text: Logic.brightnessText(root.brightness)
        font.pixelSize: root.fontSize
        color: Theme.fg
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Text {
        readonly property var sink: Pipewire.defaultAudioSink
        visible: sink !== null && sink.audio !== null
        text: visible ? "vol " + Logic.volumeText(sink.audio.volume, sink.audio.muted) : ""
        font.pixelSize: root.fontSize
        color: Theme.fg
        opacity: visible && sink.audio.muted ? 0.6 : 1.0
    }

    Text {
        readonly property var battery: UPower.displayDevice
        readonly property bool charging: battery !== null
            && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged)
        visible: battery !== null && battery.isPresent && battery.isLaptopBattery
        text: visible ? "bat " + Logic.batteryPercent(battery.percentage) + "%" + (charging ? " +" : "") : ""
        font.pixelSize: root.fontSize
        color: visible && !charging && Logic.batteryPercent(battery.percentage) <= 15 ? Theme.error : Theme.fg
    }
}
