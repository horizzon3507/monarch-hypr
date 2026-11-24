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

    Text {
        visible: !Networking.wifiEnabled
        text: "wifi off"
        font.pixelSize: root.fontSize
        color: Theme.outline
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
                    text: modelData.name + " " + Logic.signalPercent(modelData.signalStrength) + "%"
                    font.pixelSize: root.fontSize
                    color: Theme.fg
                }
            }
        }
    }

    Text {
        readonly property var adapter: Bluetooth.defaultAdapter
        visible: adapter !== null
        text: visible ? Logic.bluetoothText(adapter.enabled, connectedNames()) : ""
        font.pixelSize: root.fontSize
        color: visible && adapter.enabled ? Theme.fg : Theme.outline

        function connectedNames() {
            var out = [];
            var list = Bluetooth.devices.values;
            for (var i = 0; i < list.length; i++)
                if (list[i].connected) out.push(list[i].name);
            return out;
        }
    }
}
