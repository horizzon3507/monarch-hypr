import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "ShellLogic.js" as Logic

// Crash history of this user from `monarch-crash-history`: a list, a text
// report for one crash (`report <id>`) and a save of that report to the user's
// state folder (`export <id>`). Nothing is sent anywhere from here. Reads and
// the save go through one gate; nothing runs while another is in flight.
ColumnLayout {
    id: root
    spacing: 8

    property var crashes: null      // null: not read yet or unreadable
    property bool hasMore: false
    property bool loading: true
    property string selected: ""    // id whose report is shown, "" for the list
    property string reportText: ""
    property string savedPath: ""
    property string busy: ""
    property string errorText: ""
    property string busyNotice: ""

    readonly property bool settled: !listProc.running && busy === ""

    function refresh() {
        if (listProc.running || busy !== "") return;
        loading = true;
        listProc.running = true;
    }

    // The one gate every action goes through.
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

    function openReport(id) {
        if (!mayMutate()) return;
        selected = id; reportText = ""; savedPath = "";
        act("report", ["monarch-crash-history", "report", id]);
    }

    function save() {
        if (selected === "") return;
        act("save", ["monarch-crash-history", "export", selected]);
    }

    function back() { selected = ""; reportText = ""; savedPath = ""; errorText = ""; }

    // Keyboard scrolling of the list or report, forwarded by the panel host.
    function scrollBy(n) {
        var view = selected === "" ? rows : reportView;
        view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, view.contentY + 40 * n));
    }

    Component.onCompleted: refresh()

    Process {
        id: listProc
        command: ["monarch-crash-history", "list", "--json"]
        stdout: StdioCollector { id: listOut }
        stderr: StdioCollector { id: listErr }
        onExited: function (exitCode) {
            root.loading = false;
            var parsed = exitCode === 0 ? Logic.parseCrashList(listOut.text) : null;
            if (parsed !== null) { root.crashes = parsed.crashes; root.hasMore = parsed.hasMore; root.busyNotice = ""; return; }
            // An unreadable journal is unavailable, never "no crashes".
            var message = listErr.text.trim();
            root.errorText = message !== "" ? message : "Could not read the crash history";
        }
    }

    Process {
        id: action
        property string kind: ""
        stdout: StdioCollector { id: actionOut }
        stderr: StdioCollector { id: actionErr }
        onExited: function (exitCode) {
            root.busy = "";
            root.busyNotice = "";
            if (exitCode !== 0) {
                var message = actionErr.text.trim();
                root.errorText = message !== "" ? message : "Could not " + action.kind;
                return;
            }
            if (action.kind === "report") root.reportText = actionOut.text;
            else if (action.kind === "save") root.savedPath = Logic.parseExportPath(actionOut.text);
        }
    }

    RowLayout {
        Layout.preferredWidth: 420
        Layout.rightMargin: 24
        spacing: 8

        Text {
            text: root.selected === "" ? "Crash history" : "Crash report"
            color: Theme.fg
            font.pixelSize: 16
            font.bold: true
            Layout.fillWidth: true
        }
        Text {
            visible: root.selected !== ""
            text: "Save"
            color: Theme.accent
            font.pixelSize: 13
            opacity: root.settled && root.reportText !== "" ? 1.0 : 0.4
            MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: root.save() }
        }
        Text {
            visible: root.selected !== ""
            text: "Back"
            color: Theme.accent
            font.pixelSize: 13
            MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: root.back() }
        }
    }

    Text {
        visible: root.errorText !== "" || root.busyNotice !== ""
        text: root.busyNotice !== "" ? root.busyNotice : root.errorText
        color: Theme.error
        wrapMode: Text.Wrap
        Layout.preferredWidth: 420
    }

    Text {
        visible: root.savedPath !== ""
        text: "Saved to " + root.savedPath + " (nothing was sent)"
        color: Theme.fg
        opacity: 0.8
        font.pixelSize: 12
        wrapMode: Text.WrapAnywhere
        Layout.preferredWidth: 420
    }

    Text {
        visible: root.selected === "" && root.crashes !== null && root.crashes.length === 0
        text: "No crashes recorded for this user"
        color: Theme.fg
        opacity: 0.7
        Layout.preferredWidth: 420
    }

    Item {
        visible: root.selected === "" && root.crashes !== null && root.crashes.length > 0
        Layout.preferredWidth: 420
        Layout.preferredHeight: Math.min(rows.contentHeight, 300)

        ListView {
            id: rows
            anchors.fill: parent
            clip: true
            spacing: 2
            model: root.crashes !== null ? root.crashes : []

            delegate: Rectangle {
                id: row
                required property var modelData
                width: rows.width
                height: 36
                radius: 6
                color: "transparent"
                opacity: root.settled ? 1.0 : 0.6

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 14
                    spacing: 8
                    Text { text: row.modelData.application; color: Theme.fg; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: row.modelData.signal; color: Theme.error; font.pixelSize: 12 }
                    Text { text: row.modelData.date; color: Theme.fg; opacity: 0.6; font.pixelSize: 12 }
                }
                MouseArea { anchors.fill: parent; onClicked: root.openReport(row.modelData.id) }
            }
        }

        // A visible scroll track when the list overflows (keyboard scrolls it).
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
        visible: root.selected === "" && root.hasMore
        text: "Older crashes are not shown"
        color: Theme.fg
        opacity: 0.6
        font.pixelSize: 12
    }

    Flickable {
        id: reportView
        visible: root.selected !== ""
        Layout.preferredWidth: 420
        Layout.preferredHeight: 300
        clip: true
        contentWidth: width
        contentHeight: reportBody.implicitHeight

        Text {
            id: reportBody
            width: reportView.width - 8
            text: root.busy === "report" ? "Loading..." : root.reportText
            color: Theme.fg
            font.pixelSize: 12
            font.family: "monospace"
            wrapMode: Text.WrapAnywhere
        }
    }

    Text {
        visible: root.loading && root.crashes === null
        text: "Loading..."
        color: Theme.fg
        opacity: 0.6
    }
}
