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
        // Exclusive while a panel is open: the compositor sends keys to the
        // panel, so Escape works without a prior click. The close button below
        // is the pointer path out, and `monarch-panel close` the scripted one.
        WlrLayershell.keyboardFocus: root.current !== "" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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
            // A panel with a long list scrolls from the keyboard through scrollBy().
            Keys.onUpPressed: if (loader.item && loader.item.scrollBy) loader.item.scrollBy(-1)
            Keys.onDownPressed: if (loader.item && loader.item.scrollBy) loader.item.scrollBy(1)
            Keys.onPressed: function (event) {
                if (!loader.item || !loader.item.scrollBy) return;
                if (event.key === Qt.Key_PageUp) { loader.item.scrollBy(-8); event.accepted = true; }
                else if (event.key === Qt.Key_PageDown) { loader.item.scrollBy(8); event.accepted = true; }
            }
            Connections {
                target: window
                function onVisibleChanged() { if (window.visible) card.forceActiveFocus(); }
            }
            Component.onCompleted: forceActiveFocus()

            Rectangle {
                id: closeButton
                objectName: "closeButton"
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 8
                width: 24
                height: 24
                radius: 12
                color: Theme.surfaceVariant
                z: 10

                Text {
                    anchors.centerIn: parent
                    text: "\u00d7"
                    color: Theme.fg
                    font.pixelSize: 18
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.current = ""
                }
            }

            Loader {
                id: loader
                anchors.centerIn: parent
                active: root.current !== ""
                source: root.current === "wifi-qr" ? "WifiQr.qml" : (root.current === "network" ? "NetworkPanel.qml" : (root.current === "theme" ? "ThemePanel.qml" : (root.current === "display" ? "DisplayPanel.qml" : (root.current === "background" ? "BackgroundPanel.qml" : ""))))
            }
        }
    }
}
