import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ShellLogic.js" as Logic

// Session actions (lock, suspend, log out, reboot, shut down). Rows that end
// the session arm on the first click and run on the second; the command comes
// only from Logic.sessionCommand, never from text in this file. Suspend
// follows the suspend-off toggle, like the terminal system menu.
ColumnLayout {
    id: root
    spacing: 6

    property string armed: ""
    property bool suspendEnabled: true
    property bool hibernateAvailable: false

    readonly property var actions: Logic.sessionActions()
    // Toggles remove an option entirely, not just its row.
    readonly property var visibleActions: root.actions.filter(function (a) {
        return (a.key !== "suspend" || root.suspendEnabled) && (a.key !== "hibernate" || root.hibernateAvailable);
    })
    property int focusIndex: 0

    function scrollBy(delta) { focusIndex = Logic.moveFocus(focusIndex, delta, visibleActions.length); }
    function activateFocused() { if (visibleActions.length > 0) activate(visibleActions[focusIndex].key); }

    function activate(key) {
        if (key === "suspend" && !suspendEnabled) return;
        if (key === "hibernate" && !hibernateAvailable) return;
        var r = Logic.sessionClick(armed, key);
        armed = r.armed;
        if (r.run) {
            Quickshell.execDetached(Logic.sessionCommand(key));
            armed = "";
        }
    }

    Process {
        id: suspendProbe
        command: ["monarch-toggle-enabled", "suspend-off"]
        onExited: function (exitCode) { root.suspendEnabled = exitCode !== 0 }
    }

    Process {
        id: hibernateProbe
        command: ["monarch-hibernation-available"]
        onExited: function (exitCode) { root.hibernateAvailable = exitCode === 0 }
    }

    Component.onCompleted: {
        suspendProbe.running = true;
        hibernateProbe.running = true;
    }

    // Scripted control for tests and automation; goes through the same
    // arm/confirm flow as clicks, so confirm can never be skipped over IPC.
    IpcHandler {
        target: "session"
        function press(key: string): void { root.activate(key); }
        function armed(): string { return root.armed; }
    }

    Text {
        text: "Session"
        color: Theme.fg
        font.pixelSize: 16
        font.bold: true
        Layout.bottomMargin: 4
    }

    Repeater {
        model: root.visibleActions
        delegate: Rectangle {
            required property var modelData
            required property int index
            // Fixed width: the confirm text is longer than the label, and the
            // panel must not resize when a row arms.
            implicitWidth: 220
            implicitHeight: 34
            radius: 8
            color: root.armed === modelData.key ? Theme.error : Theme.surfaceVariant
            border.width: 2
            border.color: index === root.focusIndex ? Theme.accent : "transparent"

            Text {
                id: label
                anchors.centerIn: parent
                text: root.armed === modelData.key ? "Confirm " + modelData.label + "?" : modelData.label
                color: root.armed === modelData.key ? Theme.bg : Theme.fg
                font.pixelSize: 14
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.activate(modelData.key)
            }
        }
    }

    Text {
        visible: root.armed !== ""
        text: "Click the row again to confirm"
        color: Theme.fg
        opacity: 0.7
        font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter
        Layout.preferredWidth: 220
        Layout.topMargin: 4
    }
}
