import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ShellLogic.js" as Logic

// First-steps guide: the same phases and state files as the Noctalia plugin,
// driven through `monarch-setup-first-steps` (record, state, tools-state,
// check-updates, install-tool, visit, opened, docs). Opening only marks the
// guide as shown; a check or an install starts only from a button.
ColumnLayout {
    id: root
    spacing: 10

    readonly property string runtime: Quickshell.env("MONARCH_PATH") || "/usr/share/monarch"
    readonly property string script: runtime + "/bin/monarch-setup-first-steps"

    property string phase: "welcome"
    property bool phaseKnown: false
    property var tools: null            // null: not read yet or unreadable
    property var updateCheck: null
    property bool checking: false
    property bool launching: false
    property var shortcuts: []
    property string statusText: ""
    property int generation: 0

    readonly property bool connected: tools !== null && tools.connected
    readonly property string activeTool: tools !== null ? tools.active : ""
    readonly property var updateInfo: Logic.updateView(updateCheck, tools, connected, tools !== null, checking)
    readonly property int stepIndex: Logic.FIRST_STEPS.indexOf(phase)
    // Any async step is running: nothing else starts meanwhile.
    readonly property bool idle: !record.running && !launch.running && !checking && !launching

    function change(next) {
        if (next === "" || record.running) return;
        generation += 1; updateCheck = null; checking = false;
        record.next = next;
        record.command = [script, "record", next];
        record.running = true;
    }

    function startCheck() {
        if (phase !== "update" || tools === null || !connected || activeTool !== "" || checking) return;
        generation += 1; checking = true; updateCheck = null;
        check.gen = generation;
        check.running = true;
    }

    function loadTools() { if (!toolsProc.running) toolsProc.running = true; }

    // Visits and installs outlive this panel (the host swaps panels), so they run detached.
    function runDetached(args) {
        launch.command = ["setsid", "-f", script].concat(args);
        launch.running = true;
    }

    function install(tool) {
        if (tools === null || launching || launch.running || activeTool !== "" || (tools.installed[tool] === true)) return;
        if (tool === "update" && (!connected || checking || !updateInfo.canUpdate)) return;
        launching = true; statusText = "";
        if (tool === "update") { generation += 1; updateCheck = null; }
        launch.command = ["setsid", "-f", script, "install-tool", tool];
        launch.kind = "install";
        launch.running = true;
    }

    Component.onCompleted: { stateProc.running = true; loadTools(); shortcutProc.running = true; opened.running = true; }

    Process { id: opened; command: [root.script, "opened"] }

    Process {
        id: stateProc
        command: [root.script, "state"]
        stdout: StdioCollector { id: stateOut }
        onExited: function () { root.phase = Logic.firstStepsPhase(stateOut.text); root.phaseKnown = true; }
    }

    Process {
        id: record
        property string next: ""
        onExited: function (exitCode) {
            if (exitCode === 0) { root.phase = next; root.statusText = ""; if (next === "update") root.startCheck(); }
            else root.statusText = "Progress could not be saved.";
        }
    }

    Process {
        id: toolsProc
        command: [root.script, "tools-state"]
        stdout: StdioCollector { id: toolsOut }
        onExited: function (exitCode) {
            var parsed = exitCode === 0 ? Logic.parseToolsState(toolsOut.text) : null;
            if (parsed === null) { root.statusText = "The system state could not be read."; return; }
            if (root.tools === null || root.tools.connected !== parsed.connected || root.tools.active !== parsed.active) {
                root.generation += 1; root.updateCheck = null; root.checking = false;
            }
            root.tools = parsed;
            if (root.phase === "update" && root.updateCheck === null) root.startCheck();
            if (root.phase === "software" && parsed.lastResult !== null && parsed.lastResult.tool !== "update" && parsed.lastResult.code !== 0)
                root.statusText = "An installation was interrupted or failed. See the terminal.";
        }
    }

    Process {
        id: check
        property int gen: 0
        command: [root.script, "check-updates"]
        stdout: StdioCollector { id: checkOut }
        onExited: function (exitCode) {
            if (gen !== root.generation) return;
            root.checking = false;
            root.updateCheck = Logic.parseUpdateCheck(checkOut.text, exitCode);
        }
    }

    Process {
        id: launch
        property string kind: ""
        onExited: function (exitCode) {
            if (kind === "install") {
                root.launching = false;
                root.statusText = exitCode === 0 ? "Opened in a terminal." : "The operation could not be started.";
                root.loadTools();
            }
            kind = "";
        }
    }

    Process {
        id: shortcutProc
        command: [root.runtime + "/bin/monarch-menu-keybindings", "--json"]
        stdout: StdioCollector { id: shortcutOut }
        onExited: function (exitCode) { root.shortcuts = exitCode === 0 ? Logic.firstStepsShortcuts(shortcutOut.text) : []; }
    }

    // Refresh the live state while the steps that depend on it are showing.
    Timer {
        interval: 3000
        repeat: true
        running: root.phase === "network" || root.phase === "update" || root.phase === "software"
        onTriggered: root.loadTools()
    }

    component Entry: Rectangle {
        property string title: ""
        property string detail: ""
        property string mark: ""
        Layout.preferredWidth: 440
        implicitHeight: entryCol.implicitHeight + 20
        radius: 8
        color: Theme.surfaceVariant
        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10
            Text { text: parent.parent.mark; color: Theme.accent; font.pixelSize: 16; Layout.preferredWidth: 22 }
            ColumnLayout {
                id: entryCol
                spacing: 2
                Layout.fillWidth: true
                Text { text: parent.parent.parent.title; color: Theme.fg; font.pixelSize: 13; font.bold: true; wrapMode: Text.Wrap; Layout.fillWidth: true }
                Text { text: parent.parent.parent.detail; color: Theme.fg; opacity: 0.65; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
        }
    }

    component Action: Text {
        id: act
        property bool active: true
        signal triggered()
        color: Theme.accent
        font.pixelSize: 13
        opacity: active ? 1.0 : 0.4
        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: if (act.active) act.triggered() }
    }

    RowLayout {
        Layout.preferredWidth: 440
        Layout.rightMargin: 24
        Text { text: "First steps"; color: Theme.fg; font.pixelSize: 14; font.bold: true; Layout.fillWidth: true }
        Text {
            visible: root.stepIndex >= 0
            text: (root.stepIndex + 1) + " / " + Logic.FIRST_STEPS.length
            color: Theme.fg
            opacity: 0.55
            font.pixelSize: 11
        }
    }

    Text {
        visible: !root.phaseKnown
        text: "Loading..."
        color: Theme.fg
        opacity: 0.6
    }

    // ---- welcome / done ----
    ColumnLayout {
        visible: root.phaseKnown && (root.phase === "welcome" || root.phase === "done")
        spacing: 8
        Text { text: root.phase === "done" ? "Over to you" : "Welcome to Monarch"; color: Theme.fg; font.pixelSize: 22; Layout.preferredWidth: 440; wrapMode: Text.Wrap }
        Text {
            text: root.phase === "done" ? "Your desktop is ready. Explore it at your own pace." : "Get your system ready, then discover your desktop at your own pace."
            color: Theme.fg; opacity: 0.7; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.preferredWidth: 440
        }
        Entry { mark: "01"; title: root.phase === "done" ? "The menu is always at hand" : "Connection and updates"; detail: root.phase === "done" ? "monarch-menu, Win + Alt + Space" : "Wi-Fi or Ethernet, then the latest updates" }
        Entry { mark: "02"; title: root.phase === "done" ? "A style that is yours" : "Find your way and pick a style"; detail: root.phase === "done" ? "Themes and backgrounds are in the menu under Style." : "Shortcuts, themes and backgrounds" }
        Entry { mark: "03"; title: root.phase === "done" ? "Your tools" : "Software and cyber tools"; detail: root.phase === "done" ? "Find the cyber tools under Install." : "Install your tools one by one" }
        Text { text: "Find this guide again in monarch-menu, Learn, First steps."; color: Theme.fg; opacity: 0.65; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.preferredWidth: 440 }
    }

    // ---- network ----
    ColumnLayout {
        visible: root.phase === "network"
        spacing: 8
        Text { text: "Connect"; color: Theme.fg; font.pixelSize: 22 }
        Text { text: "Connect to update the system and install your tools."; color: Theme.fg; opacity: 0.7; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.preferredWidth: 440 }
        Entry {
            mark: root.tools === null ? "?" : (root.connected ? "\u2713" : "\u25cb")
            title: root.tools === null ? "Checking the network..." : (root.connected ? "Network connected" : "No network connection")
            detail: root.connected ? "Wi-Fi or Ethernet: you can continue." : "Pick your Wi-Fi in the network panel."
        }
        Action { text: root.connected ? "Manage the connection" : "Connect"; active: root.idle; onTriggered: root.runDetached(["visit", "network"]) }
        Text { visible: root.tools !== null && !root.connected; text: "No network available? Choose Later to continue the tour."; color: Theme.fg; opacity: 0.65; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.preferredWidth: 440 }
    }

    // ---- update ----
    ColumnLayout {
        visible: root.phase === "update"
        spacing: 8
        Text { text: "Update Monarch"; color: Theme.fg; font.pixelSize: 22 }
        Entry { mark: "\u21bb"; title: root.updateInfo.title; detail: root.updateInfo.detail }
        Action { visible: root.updateInfo.canUpdate; text: root.updateInfo.button; active: root.idle; onTriggered: root.install("update") }
        Action {
            text: root.checking ? "Checking..." : (root.updateCheck !== null && root.updateCheck.status === "error" ? "Retry" : "Check again")
            active: root.idle && root.tools !== null && root.connected && root.activeTool === ""
            onTriggered: root.startCheck()
        }
        Action { visible: root.tools !== null && !root.connected; text: "Connect"; active: root.idle; onTriggered: root.runDetached(["visit", "network"]) }
        Text { visible: root.updateInfo.canUpdate; text: "The guide closes during the operation. Confirm the end in the terminal to come back here."; color: Theme.fg; opacity: 0.65; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.preferredWidth: 440 }
    }

    // ---- shortcuts ----
    ColumnLayout {
        visible: root.phase === "shortcuts"
        spacing: 8
        Text { text: "Find your way"; color: Theme.fg; font.pixelSize: 22 }
        Text { text: "A few shortcuts to start. Win is the Windows key."; color: Theme.fg; opacity: 0.7; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.preferredWidth: 440 }
        Text { visible: root.shortcuts.length === 0; text: "Open the list of active shortcuts."; color: Theme.fg; font.pixelSize: 13 }
        Repeater {
            model: root.shortcuts
            delegate: Rectangle {
                required property var modelData
                Layout.preferredWidth: 440
                implicitHeight: 38
                radius: 8
                color: Theme.surfaceVariant
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    Text { text: modelData.label; color: Theme.fg; font.pixelSize: 13; Layout.fillWidth: true }
                    Text { text: modelData.shortcut; color: Theme.accent; font.pixelSize: 12 }
                }
            }
        }
        Action { text: "See all shortcuts"; active: root.idle; onTriggered: root.runDetached(["visit", "shortcuts"]) }
    }

    // ---- appearance ----
    ColumnLayout {
        visible: root.phase === "appearance"
        spacing: 8
        Text { text: "Pick a style"; color: Theme.fg; font.pixelSize: 22 }
        Text { text: "Choose a palette and a background that suit you."; color: Theme.fg; opacity: 0.7; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.preferredWidth: 440 }
        Entry { mark: "\u25d0"; title: "Themes"; detail: "One palette shared by the desktop and your apps." }
        Entry { mark: "\u25a7"; title: "Backgrounds"; detail: "Open the background panel from the menu, or run monarch-panel toggle background." }
        Action { text: "Explore themes"; active: root.idle; onTriggered: root.runDetached(["visit", "appearance"]) }
        Text { text: "Close the panel you opened to come back to this step."; color: Theme.fg; opacity: 0.55; font.pixelSize: 11; Layout.preferredWidth: 440; wrapMode: Text.Wrap }
    }

    // ---- software ----
    ColumnLayout {
        visible: root.phase === "software"
        spacing: 8
        Text { text: "Software and cyber tools"; color: Theme.fg; font.pixelSize: 22 }
        Text { text: "Caido and Exegol are included. Install other tools one by one."; color: Theme.fg; opacity: 0.75; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.preferredWidth: 440 }
        Repeater {
            model: [
                { id: "burpsuite", name: "Burp Suite", detail: "Web testing, Community or Pro" },
                { id: "rfswift", name: "RF Swift", detail: "Environments for radio and hardware testing" },
                { id: "seclists", name: "SecLists", detail: "Word lists for security testing" }
            ]
            delegate: Rectangle {
                required property var modelData
                readonly property bool present: root.tools !== null && root.tools.installed[modelData.id] === true
                Layout.preferredWidth: 440
                implicitHeight: 54
                radius: 8
                color: Theme.surfaceVariant
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        Text { text: modelData.name; color: Theme.fg; font.pixelSize: 13; font.bold: true }
                        Text { text: modelData.detail; color: Theme.fg; opacity: 0.65; font.pixelSize: 11 }
                    }
                    Text { visible: present; text: "\u2713 Installed"; color: Theme.accent; font.pixelSize: 11; Layout.preferredWidth: 96; horizontalAlignment: Text.AlignRight }
                    Action {
                        visible: !present
                        Layout.preferredWidth: 96
                        horizontalAlignment: Text.AlignRight
                        text: root.activeTool === modelData.id ? "In progress..." : "Install"
                        active: root.idle && root.tools !== null && root.activeTool === ""
                        onTriggered: root.install(modelData.id)
                    }
                }
            }
        }
        RowLayout {
            spacing: 16
            Action { text: "Install software"; active: root.idle; onTriggered: root.runDetached(["visit", "software"]) }
            Action { text: "Cyber catalog"; active: root.idle; onTriggered: root.runDetached(["visit", "cyber"]) }
        }
        Text { text: "The guide closes during an installation. Confirm the end in the terminal to come back here."; color: Theme.fg; opacity: 0.55; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.preferredWidth: 440 }
    }

    Text {
        visible: root.statusText !== ""
        text: root.statusText
        color: Theme.fg
        opacity: 0.75
        font.pixelSize: 11
        wrapMode: Text.Wrap
        Layout.preferredWidth: 440
    }

    // ---- navigation ----
    RowLayout {
        visible: root.phaseKnown
        Layout.preferredWidth: 440
        spacing: 16
        Action {
            text: root.phase === "welcome" ? "Skip" : (root.phase === "done" ? "Start the tour again" : "Back")
            active: root.idle
            onTriggered: root.phase === "welcome" ? Quickshell.execDetached([root.runtime + "/bin/monarch-panel", "close"]) : root.change(root.phase === "done" ? "welcome" : Logic.prevPhase(root.phase))
        }
        Item { Layout.fillWidth: true }
        Action { text: "Documentation"; active: true; onTriggered: root.runDetached(["docs"]) }
        Action {
            text: root.phase === "welcome" ? "Start" : (root.phase === "done" ? "Done" : (root.stepIndex === Logic.FIRST_STEPS.length - 1 ? "Finish"
                : ((root.phase === "network" && !root.connected) || (root.phase === "update" && !root.updateInfo.current) ? "Later" : "Continue")))
            active: root.idle
            onTriggered: root.phase === "done" ? Quickshell.execDetached([root.runtime + "/bin/monarch-panel", "close"]) : root.change(Logic.nextPhase(root.phase))
        }
    }
}
