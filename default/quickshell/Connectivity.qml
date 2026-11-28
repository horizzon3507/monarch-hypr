import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import Quickshell.Bluetooth
import "ShellLogic.js" as Logic

// Network and Bluetooth readouts. Every Text binds to the live objects, so a
// connection change updates only that label. Nothing shows when the service
// (NetworkManager, BlueZ) is absent or has nothing connected.
RowLayout {
    id: root
    spacing: 12
    property int fontSize: 13
    // Compact mode (narrow bars): drop the wifi network name, keep the
    // signal strength; bluetooth shortens to "bt".
    property bool compact: false

    // "Wi-Fi is off" is only claimed when NetworkManager is the backend and it
    // reports devices. With no backend (no daemon) wifiEnabled is false too, and
    // that must not read as the user having turned Wi-Fi off.
    Text {
        visible: Networking.backend !== NetworkBackendType.None
            && Networking.devices.values.length > 0
            && !Networking.wifiEnabled
        text: "wifi off"
        font.pixelSize: root.fontSize
        color: Theme.fg
        opacity: 0.6
    }

    Repeater {
        model: Networking.devices

        delegate: RowLayout {
            id: device
            required property var modelData
            spacing: 12

            Text {
                visible: device.modelData.type === DeviceType.Wired && device.modelData.connected
                text: "eth"
                font.pixelSize: root.fontSize
                color: Theme.fg
            }

            Repeater {
                model: device.modelData.type === DeviceType.Wifi ? device.modelData.networks : null

                delegate: Text {
                    required property var modelData
                    visible: modelData.connected
                    text: root.compact
                        ? Logic.signalPercent(modelData.signalStrength) + "%"
                        : modelData.name + " " + Logic.signalPercent(modelData.signalStrength) + "%"
                    font.pixelSize: root.fontSize
                    color: Theme.fg
                }
            }
        }
    }

    Text {
        readonly property var adapter: Bluetooth.defaultAdapter
        visible: adapter !== null
        text: visible ? (root.compact ? "bt" : Logic.bluetoothText(adapter.enabled, connectedNames())) : ""
        font.pixelSize: root.fontSize
        color: Theme.fg
        opacity: visible && adapter.enabled ? 1.0 : 0.6

        function connectedNames() {
            var out = [];
            var list = Bluetooth.devices.values;
            for (var i = 0; i < list.length; i++)
                if (list[i].connected) out.push(list[i].name);
            return out;
        }
    }
}
