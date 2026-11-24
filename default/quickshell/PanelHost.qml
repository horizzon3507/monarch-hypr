import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "ShellLogic.js" as Logic

// Hosts one panel at a time in a centered overlay window. Monarch commands
// drive it through `monarch-panel`, which calls the IPC handler below.
Scope {
    id: root

    property string current: ""

    IpcHandler {
        target: "panel"

        function toggle(name: string): void { root.current = Logic.togglePanel(root.current, name); }
        function open(name: string): void {
            var next = Logic.panelName(name);
            if (next !== "") root.current = next;
        }
        function close(): void { root.current = ""; }
        function active(): string { return root.current; }
    }

    PanelWindow {
        id: window
        visible: root.current !== ""
        color: "transparent"
        implicitWidth: card.implicitWidth
        implicitHeight: card.implicitHeight
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "monarch-panel"

        Rectangle {
            id: card
            implicitWidth: loader.implicitWidth + 40
            implicitHeight: loader.implicitHeight + 40
            color: Theme.bg
            border.color: Theme.outline
            border.width: 1
            radius: 10

            focus: true
            Keys.onEscapePressed: root.current = ""

            Loader {
                id: loader
                anchors.centerIn: parent
                active: root.current === "wifi-qr"
                source: root.current === "wifi-qr" ? "WifiQr.qml" : ""
            }
        }
    }
}
