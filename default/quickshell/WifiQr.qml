import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "ShellLogic.js" as Logic

// The connected Wi-Fi network as a QR code, with the password behind one
// deliberate click. The code is a PNG data URI from `monarch-wifi-qr --data`
// (qrencode); it is held in memory only and nothing is written to disk.
ColumnLayout {
    id: root
    spacing: 12

    property var info: null        // parsed meta line, null until generated
    property string errorText: ""
    property string password: ""
    property bool passwordVisible: false
    property string passwordError: ""

    readonly property bool secured: info !== null && Logic.wifiSecured(info.security)

    function generate() {
        // A card being regenerated is a different card: drop the secret with it.
        info = null; errorText = ""; password = ""; passwordVisible = false; passwordError = "";
        qr.running = true;
    }

    Component.onCompleted: generate()

    // Leaving the panel drops the secret and the image; the host unloads this item.
    Component.onDestruction: { password = ""; info = null; }

    Process {
        id: qr
        command: ["monarch-wifi-qr", "--data"]
        stdout: StdioCollector {
            id: qrOut
        }
        stderr: StdioCollector {
            id: qrErr
        }
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                var message = qrErr.text.trim();
                root.errorText = message !== "" ? message : "Could not generate the Wi-Fi QR code";
                return;
            }
            var parsed = Logic.parseWifiQr(qrOut.text);
            if (parsed === null) root.errorText = "Could not read the Wi-Fi QR code";
            else root.info = parsed;
        }
    }

    Process {
        id: reveal
        command: ["monarch-wifi-password", root.info ? root.info.iface : ""]
        stdout: StdioCollector {
            id: revealOut
        }
        stderr: StdioCollector {
            id: revealErr
        }
        onExited: function (exitCode) {
            var text = revealOut.text.trim();
            if (exitCode === 0 && text !== "") {
                root.password = text;
                root.passwordVisible = true;
            } else {
                var message = revealErr.text.trim();
                root.passwordError = message !== "" ? message : "Could not read the Wi-Fi password";
            }
        }
    }

    Text {
        text: root.info ? root.info.ssid : "Wi-Fi"
        color: Theme.fg
        font.pixelSize: 18
        font.bold: true
        Layout.alignment: Qt.AlignHCenter
    }

    Image {
        visible: root.info !== null
        source: root.info ? root.info.image : ""
        cache: false
        sourceSize.width: 320
        sourceSize.height: 320
        Layout.preferredWidth: 320
        Layout.preferredHeight: 320
        Layout.alignment: Qt.AlignHCenter
        smooth: false
    }

    Text {
        visible: root.info === null && root.errorText === ""
        text: "Generating..."
        color: Theme.fg
        opacity: 0.6
        Layout.alignment: Qt.AlignHCenter
    }

    Text {
        visible: root.errorText !== ""
        text: root.errorText
        color: Theme.error
        wrapMode: Text.Wrap
        Layout.preferredWidth: 320
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignHCenter
    }

    Text {
        visible: root.info !== null
        text: "Scan to join this network"
        color: Theme.fg
        opacity: 0.6
        Layout.alignment: Qt.AlignHCenter
    }

    Rectangle {
        visible: root.secured
        color: Theme.surfaceVariant
        radius: 6
        implicitWidth: 320
        implicitHeight: 36
        Layout.alignment: Qt.AlignHCenter

        Text {
            anchors.centerIn: parent
            text: root.passwordVisible ? root.password : "Show password"
            color: Theme.fg
            font.pixelSize: 14
        }
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (root.passwordVisible) {
                    root.password = ""; root.passwordVisible = false;
                } else {
                    root.passwordError = "";
                    reveal.running = true;
                }
            }
        }
    }

    Text {
        visible: root.passwordError !== ""
        text: root.passwordError
        color: Theme.error
        wrapMode: Text.Wrap
        Layout.preferredWidth: 320
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignHCenter
    }
}
