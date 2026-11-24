import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "ShellLogic.js" as Logic

// Theme picker: the Monarch themes from `monarch-theme-list`, the dark/light
// switch (`monarch-theme-mode`) and `monarch-theme-set`. State changes go
// through one gate (mayMutate) and never run while a read or change is in flight.
ColumnLayout {
    id: root
    spacing: 8

    property var themes: null       // null: not read yet or unreadable
    property string mode: ""        // "dark", "light" or "" when unknown
    property bool loading: true
    property string busy: ""
    property string errorText: ""      // a real failure; stays until the next action
    property string busyNotice: ""     // "busy" hint; goes away once things settle

    readonly property bool settled: !listProc.running && !modeProc.running && busy === ""

    function refresh() {
        if (listProc.running || modeProc.running || busy !== "") return;
        loading = true;
        listProc.running = true;
        modeProc.running = true;
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

    // Keyboard scrolling, forwarded by the panel host (Up/Down/PageUp/PageDown).
    function scrollBy(rowsCount) {
        var step = 36 * rowsCount;
        rows.contentY = Math.max(0, Math.min(rows.contentHeight - rows.height, rows.contentY + step));
    }

    Component.onCompleted: refresh()

    Process {
        id: listProc
        command: ["monarch-theme-list"]
        stdout: StdioCollector { id: listOut }
        onExited: function (exitCode) {
            root.loading = false;
            var parsed = exitCode === 0 ? Logic.parseThemeList(listOut.text) : null;
            if (parsed !== null) { root.themes = parsed; root.busyNotice = ""; }
            else if (root.themes === null) root.errorText = "Could not read the themes";
        }
    }

    Process {
        id: modeProc
        command: ["monarch-theme-mode", "get"]
        stdout: StdioCollector { id: modeOut }
        onExited: function (exitCode) { root.mode = exitCode === 0 ? Logic.parseThemeMode(modeOut.text) : ""; }
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

    RowLayout {
        Layout.preferredWidth: 320
        Layout.rightMargin: 24
        spacing: 8

        Text {
            text: "Theme"
            color: Theme.fg
            font.pixelSize: 16
            font.bold: true
            Layout.fillWidth: true
        }
        Repeater {
            model: ["dark", "light"]
            delegate: Text {
                required property string modelData
                text: modelData === "dark" ? "Dark" : "Light"
                color: root.mode === modelData ? Theme.fg : Theme.accent
                font.bold: root.mode === modelData
                font.pixelSize: 13
                opacity: root.settled ? 1.0 : 0.5
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.act("mode", ["monarch-theme-mode", modelData])
                }
            }
        }
    }

    Text {
        visible: root.errorText !== "" || root.busyNotice !== ""
        text: root.busyNotice !== "" ? root.busyNotice : root.errorText
        color: Theme.error
        wrapMode: Text.Wrap
        Layout.preferredWidth: 320
    }

    Item {
        id: listWrap
        Layout.preferredWidth: 320
        Layout.preferredHeight: Math.min(rows.contentHeight, 320)

        ListView {
            id: rows
            anchors.fill: parent
            clip: true
            spacing: 2
            model: root.themes !== null ? root.themes : []

            delegate: Rectangle {
                id: row
                required property var modelData
                width: rows.width
                height: 34
                radius: 6
                color: modelData.selected ? Theme.surfaceVariant : "transparent"
                border.width: modelData.selected ? 1 : 0
                border.color: Theme.accent
                opacity: root.settled ? 1.0 : 0.6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 10
                    text: row.modelData.name
                    color: Theme.fg
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.act("theme", ["monarch-theme-set", row.modelData.name])
                }
            }
        }

        // A visible scroll track: the list has more rows than fit.
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
        visible: root.loading && root.themes === null
        text: "Loading..."
        color: Theme.fg
        opacity: 0.6
    }
}
