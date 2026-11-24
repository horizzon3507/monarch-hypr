import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ShellLogic.js" as Logic

// Coding-provider usage from `monarch-agent-usage-fetch` (CodexBar). Read
// only; provider setup stays in the terminal (`monarch-agent-usage manage`).
ColumnLayout {
    id: root
    spacing: 8

    property var providers: null    // null: not read yet or unreadable
    property bool loading: true
    property string errorText: ""
    property string selectedKey: ""

    readonly property var selected: {
        if (providers === null || providers.length === 0) return null;
        for (var i = 0; i < providers.length; i++) if (providers[i].key === selectedKey) return providers[i];
        return providers[0];
    }

    function refresh() {
        if (fetch.running) return;
        loading = true; errorText = "";
        fetch.running = true;
    }

    function scrollBy(n) {
        var v = windowsView;
        v.contentY = Math.max(0, Math.min(Math.max(0, v.contentHeight - v.height), v.contentY + 40 * n));
    }

    Component.onCompleted: refresh()

    Process {
        id: fetch
        command: ["monarch-agent-usage-fetch"]
        stdout: StdioCollector { id: fetchOut }
        onExited: function (exitCode) {
            root.loading = false;
            var parsed = exitCode === 0 ? Logic.parseUsage(fetchOut.text) : null;
            if (parsed === null) { root.errorText = "Could not read the usage. Check that codexbar is installed."; return; }
            root.providers = parsed.providers;
            if (!parsed.ok) root.errorText = "Some providers could not be read.";
        }
    }

    RowLayout {
        Layout.preferredWidth: 420
        Layout.rightMargin: 24
        Text { text: "Agent usage"; color: Theme.fg; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
        Text {
            text: root.loading ? "Loading..." : "Refresh"
            color: Theme.accent
            font.pixelSize: 13
            opacity: root.loading ? 0.5 : 1.0
            MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: root.refresh() }
        }
    }

    Text {
        visible: root.errorText !== ""
        text: root.errorText
        color: Theme.error
        wrapMode: Text.Wrap
        Layout.preferredWidth: 420
    }

    Text {
        visible: root.providers !== null && root.providers.length === 0
        text: "No provider is enabled. Use Manage providers."
        color: Theme.fg
        opacity: 0.7
        Layout.preferredWidth: 420
    }

    Flow {
        visible: root.providers !== null && root.providers.length > 1
        spacing: 12
        Layout.preferredWidth: 420
        Repeater {
            model: root.providers !== null ? root.providers : []
            delegate: Text {
                required property var modelData
                text: modelData.name
                color: root.selected !== null && root.selected.key === modelData.key ? Theme.accent : Theme.fg
                font.pixelSize: 13
                font.bold: root.selected !== null && root.selected.key === modelData.key
                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: root.selectedKey = modelData.key }
            }
        }
    }

    ColumnLayout {
        visible: root.selected !== null
        spacing: 6
        Layout.preferredWidth: 420
        Text { text: root.selected !== null ? root.selected.name : ""; color: Theme.fg; font.pixelSize: 15; font.bold: true }
        Text { visible: root.selected !== null && root.selected.plan !== ""; text: root.selected !== null ? root.selected.plan : ""; color: Theme.fg; opacity: 0.6; font.pixelSize: 11 }
        Text { visible: root.selected !== null && root.selected.issue !== ""; text: root.selected !== null ? root.selected.issue : ""; color: Theme.error; wrapMode: Text.Wrap; Layout.preferredWidth: 420 }
        Repeater {
            model: root.selected !== null ? root.selected.lines : []
            delegate: Text { required property string modelData; text: modelData; color: Theme.fg; font.pixelSize: 12 }
        }
        Text { visible: root.selected !== null && root.selected.stale; text: "These numbers may be out of date."; color: Theme.secondary; font.pixelSize: 11 }
        Text { visible: root.selected !== null && root.selected.empty; text: "No quota information for this provider."; color: Theme.fg; opacity: 0.6 }
    }

    Item {
        visible: root.selected !== null && root.selected.windows.length > 0
        Layout.preferredWidth: 420
        Layout.preferredHeight: Math.min(windowsView.contentHeight, 260)
        ListView {
            id: windowsView
            anchors.fill: parent
            clip: true
            spacing: 8
            model: root.selected !== null ? root.selected.windows : []
            delegate: ColumnLayout {
                id: win
                required property var modelData
                width: windowsView.width - 10
                spacing: 3
                RowLayout {
                    Text { text: win.modelData.title; color: Theme.fg; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text {
                        text: win.modelData.used.toFixed(1) + "%"
                        font.pixelSize: 12
                        font.bold: true
                        color: Logic.usageColor(win.modelData.used) === "error" ? Theme.error : (Logic.usageColor(win.modelData.used) === "warn" ? Theme.secondary : Theme.accent)
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 6
                    radius: 3
                    color: Theme.surfaceVariant
                    Rectangle {
                        width: parent.width * win.modelData.used / 100
                        height: parent.height
                        radius: 3
                        color: Logic.usageColor(win.modelData.used) === "error" ? Theme.error : (Logic.usageColor(win.modelData.used) === "warn" ? Theme.secondary : Theme.accent)
                    }
                }
                Text { visible: win.modelData.reset !== ""; text: "Resets " + win.modelData.reset; color: Theme.fg; opacity: 0.6; font.pixelSize: 11 }
            }
        }
        Rectangle {
            visible: windowsView.contentHeight > windowsView.height
            anchors.right: parent.right
            width: 4
            radius: 2
            height: parent.height * (windowsView.height / Math.max(windowsView.contentHeight, 1))
            y: windowsView.height * (windowsView.contentY / Math.max(windowsView.contentHeight, 1))
            color: Theme.accent
            opacity: 0.7
            z: 5
        }
    }

    Text {
        text: "Manage providers"
        color: Theme.accent
        font.pixelSize: 13
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: {
                Quickshell.execDetached(["monarch-launch-tui", "--app-id=org.monarch.agent-usage", "monarch-agent-usage", "manage"]);
                Quickshell.execDetached(["monarch-panel", "close"]);
            }
        }
    }
}
