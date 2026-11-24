import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "ShellLogic.js" as Logic

// Wi-Fi networks from NetworkManager through `monarch-wifi-panel list`: list,
// rescan, join (saved or open networks), disconnect, forget and the radio switch.
// Joining a new password-protected network is not handled here yet.
ColumnLayout {
    id: root
    spacing: 8

    property var snapshot: null
    property bool loading: true
    property string busy: ""        // action in flight, "" when idle
    property string errorText: ""

    readonly property string header: Logic.wifiHeader(snapshot)

    function refresh(rescan) {
        if (list.running) return;
        loading = true;
        list.command = rescan ? ["monarch-wifi-panel", "list", "--rescan"] : ["monarch-wifi-panel", "list"];
        list.running = true;
    }

    function act(kind, command) {
        if (busy !== "") return;
        busy = kind; errorText = "";
        action.kind = kind;
        action.command = command;
        action.running = true;
    }

    function activate(net) {
        var what = Logic.wifiRowAction(net);
        if (what === "join") act("join", ["monarch-wifi-join", net.ssid]);
        else if (what === "disconnect") act("disconnect", ["monarch-wifi-panel", "disconnect", net.device, net.uuid]);
        else if (what === "credentials") errorText = net.ssid + " needs a password: use `monarch wifi connect` for now";
    }

    Component.onCompleted: refresh(false)

    Process {
        id: list
        stdout: StdioCollector { id: listOut }
        stderr: StdioCollector { id: listErr }
        onExited: function (exitCode) {
            root.loading = false;
            if (exitCode === 0) {
                var parsed = Logic.parseWifiSnapshot(listOut.text);
                if (parsed !== null) { root.snapshot = parsed; return; }
            }
            // The last good list stands when a refresh fails.
            var message = listErr.text.trim();
            root.errorText = message !== "" ? message : "Could not read the Wi-Fi networks";
        }
    }

    Process {
        id: action
        property string kind: ""
        stderr: StdioCollector { id: actionErr }
        onExited: function (exitCode) {
            root.busy = "";
            if (exitCode !== 0) {
                var message = actionErr.text.trim();
                root.errorText = message !== "" ? message : "Could not " + action.kind;
            }
            root.refresh(false);
        }
    }

    Process {
        id: radio
        command: ["monarch-toggle-wifi", "toggle"]
        onExited: root.refresh(false)
    }

    RowLayout {
        Layout.preferredWidth: 380
        spacing: 8

        Text {
            text: root.header
            color: Theme.fg
            font.pixelSize: 16
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Text {
            visible: root.snapshot !== null && root.snapshot.present
            text: root.snapshot !== null && root.snapshot.enabled ? "Turn off" : "Turn on"
            color: Theme.accent
            font.pixelSize: 13
            MouseArea { anchors.fill: parent; onClicked: radio.running = true }
        }
        Text {
            visible: root.snapshot !== null && root.snapshot.present && root.snapshot.enabled
            text: root.loading ? "Scanning..." : "Rescan"
            color: Theme.accent
            opacity: root.loading ? 0.6 : 1.0
            font.pixelSize: 13
            MouseArea { anchors.fill: parent; onClicked: root.refresh(true) }
        }
    }

    Text {
        visible: root.errorText !== ""
        text: root.errorText
        color: Theme.error
        wrapMode: Text.Wrap
        Layout.preferredWidth: 380
    }

    ListView {
        id: rows
        Layout.preferredWidth: 380
        Layout.preferredHeight: Math.min(contentHeight, 320)
        clip: true
        spacing: 2
        model: root.snapshot !== null && root.snapshot.enabled ? root.snapshot.networks : []

        delegate: Rectangle {
            id: row
            required property var modelData
            width: rows.width
            height: 36
            radius: 6
            color: modelData.connected ? Theme.surfaceVariant : "transparent"
            border.width: modelData.connected ? 1 : 0
            border.color: Theme.accent

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: row.modelData.ssid
                    color: Theme.fg
                    font.pixelSize: 14
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: row.modelData.connecting ? "connecting" : (row.modelData.connected ? "connected" : (row.modelData.saved ? "saved" : ""))
                    color: Theme.fg
                    opacity: 0.6
                    font.pixelSize: 12
                }
                Text {
                    text: row.modelData.security === "open" ? "open" : row.modelData.security
                    color: Theme.fg
                    opacity: 0.6
                    font.pixelSize: 12
                }
                Text {
                    text: row.modelData.signal + "%"
                    color: Theme.fg
                    font.pixelSize: 12
                }
                Text {
                    visible: row.modelData.saved
                    text: "Forget"
                    color: Theme.error
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.act("forget", ["monarch-wifi-panel", "forget", row.modelData.uuid])
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: root.activate(row.modelData)
            }
        }
    }

    Text {
        visible: root.loading && root.snapshot === null
        text: "Loading..."
        color: Theme.fg
        opacity: 0.6
    }
}
