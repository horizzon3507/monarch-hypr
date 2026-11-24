import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import "ShellLogic.js" as Logic

// Battery and volume readouts. Each hides itself when its service has nothing
// to show (no battery, no default sink).
RowLayout {
    id: root
    spacing: 12
    property int fontSize: 13

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Text {
        readonly property var sink: Pipewire.defaultAudioSink
        visible: sink !== null && sink.audio !== null
        text: visible ? "vol " + Logic.volumeText(sink.audio.volume, sink.audio.muted) : ""
        font.pixelSize: root.fontSize
        color: visible && sink.audio.muted ? Theme.outline : Theme.fg
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
