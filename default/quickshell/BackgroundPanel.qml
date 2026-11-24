import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "ShellLogic.js" as Logic

// Backgrounds of the active theme from `monarch-theme-background-list`; a click
// runs `monarch-wallpaper set <path>`. Same gate as the other panels: nothing
// runs while a read or change is in flight.
ColumnLayout {
    id: root
    spacing: 8

    property var items: null        // null: not read yet or the command failed
    property bool loading: true
    property string busy: ""
    property string errorText: ""   // a real failure; stays until the next action
    property string busyNotice: ""  // goes away once things settle

    readonly property bool settled: !listProc.running && busy === ""

    function refresh() {
        if (listProc.running || busy !== "") return;
        loading = true;
        listProc.running = true;
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

    // Keyboard scrolling, forwarded by the panel host.
    function scrollBy(rowsCount) {
        var step = 44 * rowsCount;
        rows.contentY = Math.max(0, Math.min(rows.contentHeight - rows.height, rows.contentY + step));
    }

    Component.onCompleted: refresh()

    Process {
        id: listProc
        command: ["monarch-theme-background-list"]
        stdout: StdioCollector { id: listOut }
        stderr: StdioCollector { id: listErr }
        onExited: function (exitCode) {
            root.loading = false;
            var parsed = exitCode === 0 ? Logic.parseBackgroundList(listOut.text) : null;
            if (parsed !== null) { root.items = parsed; root.busyNotice = ""; return; }
            // A failed or unrecognized read is unavailable, never an empty list.
            var message = exitCode !== 0 ? listErr.text.trim() : "";
            root.errorText = message !== "" ? message : "Could not read the backgrounds";
        }
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
                root.errorText = message !== "" ? message : "Could not " + action.kind;
            }
            root.refresh();
        }
    }

    Text {
        text: "Backgrounds"
        color: Theme.fg
        font.pixelSize: 16
        font.bold: true
        Layout.preferredWidth: 320
        Layout.rightMargin: 24
    }

    Text {
        visible: root.errorText !== "" || root.busyNotice !== ""
        text: root.busyNotice !== "" ? root.busyNotice : root.errorText
        color: Theme.error
        wrapMode: Text.Wrap
        Layout.preferredWidth: 320
    }

    Text {
        visible: root.items !== null && root.items.length === 0
        text: "This theme has no backgrounds"
        color: Theme.fg
        opacity: 0.7
        Layout.preferredWidth: 320
    }

    Item {
        id: listWrap
        visible: root.items !== null && root.items.length > 0
        Layout.preferredWidth: 320
        Layout.preferredHeight: Math.min(rows.contentHeight, 308)

        ListView {
            id: rows
            anchors.fill: parent
            clip: true
            spacing: 2
            model: root.items !== null ? root.items : []

            delegate: Rectangle {
                id: row
                required property var modelData
                width: rows.width
                height: 44
                radius: 6
                color: modelData.active ? Theme.surfaceVariant : "transparent"
                border.width: modelData.active ? 1 : 0
                border.color: Theme.accent
                // A file the image loader rejects is listed but not selectable.
                readonly property bool broken: thumb.status === Image.Error
                opacity: broken ? 0.4 : (root.settled ? 1.0 : 0.6)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 12
                    spacing: 10

                    Image {
                        id: thumb
                        visible: row.modelData.thumbnail !== ""
                        source: row.modelData.thumbnail !== "" ? "file://" + row.modelData.thumbnail : ""
                        sourceSize.width: 64
                        sourceSize.height: 36
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36
                    }
                    Text {
                        text: row.broken ? row.modelData.name + " (not a usable image)" : row.modelData.name
                        color: Theme.fg
                        font.pixelSize: 13
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: if (!row.broken) root.act("background", ["monarch-wallpaper", "set", row.modelData.path])
                }
            }
        }

        // A visible scroll track: the list has more rows than fit (keyboard scrolls it).
        Rectangle {
            visible: rows.contentHeight > rows.height
            anchors.right: parent.right
            anchors.top: parent.top
            width: 4
            radius: 2
            height: parent.height * (rows.height / Math.max(rows.contentHeight, 1))
            y: rows.height * (rows.contentY / Math.max(rows.contentHeight, 1))
            color: Theme.accent
            opacity: 0.7
            z: 5
        }
    }

    Text {
        visible: root.loading && root.items === null
        text: "Loading..."
        color: Theme.fg
        opacity: 0.6
    }
}
