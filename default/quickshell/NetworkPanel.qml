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
    // Three message slots so a good refresh clears only what it made obsolete:
    // a notice (stale or password hint) and a list error go away with the next
    // good list; an action error stays until the next action starts.
    property string noticeText: ""
    property string listError: ""
    property string actionError: ""
    readonly property string errorText: noticeText !== "" ? noticeText : (actionError !== "" ? actionError : listError)
    // True when the last refresh failed: the list on screen is the last good
    // one and may not match the machine, so it is shown dimmed and nothing that
    // acts on it (join, disconnect, forget, radio) is allowed until a refresh works.
    property bool stale: false

    readonly property string header: Logic.wifiHeader(stale ? null : snapshot)

    function refresh(rescan) {
        if (list.running) return;
        loading = true;
        list.command = rescan ? ["monarch-wifi-panel", "list", "--rescan"] : ["monarch-wifi-panel", "list"];
        list.running = true;
    }

    function act(kind, command) {
        if (busy !== "") return;
        busy = kind; actionError = ""; noticeText = "";
        action.kind = kind;
        action.command = command;
        action.running = true;
    }

    function activate(net) {
        var what = Logic.wifiRowAction(net, stale);
        if (what === "join") act("join", ["monarch-wifi-join", net.ssid]);
        else if (what === "disconnect") act("disconnect", ["monarch-wifi-panel", "disconnect", net.device, net.uuid]);
        else if (what === "" && stale) noticeText = "The Wi-Fi state is out of date: rescan first";
        else if (what === "credentials") noticeText = net.ssid + " needs a password: use `monarch wifi connect` for now";
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
                if (parsed !== null) { root.snapshot = parsed; root.stale = false; root.listError = ""; root.noticeText = ""; return; }
            }
            // The last good list stays visible but stale.
            root.stale = true;
            var message = listErr.text.trim();
            root.listError = message !== "" ? message : "Could not read the Wi-Fi networks";
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
                root.actionError = message !== "" ? message : "Could not " + action.kind;
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
        // Keep the header clear of the host's close button in the card corner.
        Layout.rightMargin: 24
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
            visible: root.snapshot !== null && root.snapshot.present && !root.stale
            text: root.snapshot !== null && root.snapshot.enabled ? "Turn off" : "Turn on"
            color: Theme.accent
            font.pixelSize: 13
            MouseArea {
                anchors.fill: parent
                enabled: Logic.wifiRadioEnabled(root.snapshot, root.stale)
                onClicked: radio.running = true
            }
            opacity: Logic.wifiRadioEnabled(root.snapshot, root.stale) ? 1.0 : 0.4
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
            // A long name elides; the "More" control wraps the full name. It is
            // separate from the row click, so reading a name never joins.
            property bool expanded: false
            height: Math.max(36, ssidText.implicitHeight + 16)
            opacity: root.stale ? 0.5 : 1.0
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
                    id: ssidText
                    text: row.modelData.ssid
                    color: Theme.fg
                    font.pixelSize: 14
                    elide: row.expanded ? Text.ElideNone : Text.ElideRight
                    wrapMode: row.expanded ? Text.WrapAnywhere : Text.NoWrap
                    Layout.fillWidth: true
                }
                Text {
                    visible: row.expanded || ssidText.truncated
                    text: row.expanded ? "Less" : "More"
                    color: Theme.accent
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        z: 2
                        onClicked: row.expanded = !row.expanded
                    }
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
                    visible: row.modelData.saved && !root.stale
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
