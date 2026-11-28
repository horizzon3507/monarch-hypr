import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray

// Status notifier icons. Left click activates, right click opens the item menu,
// middle click does the secondary action. When the bar caps the tray to fit a
// narrow screen, extra items collapse behind a "+N" chip whose popup keeps
// them clickable instead of silently clipping them away.
RowLayout {
    id: root
    spacing: 8
    property int iconSize: 16
    // -1 = show every item; 0 or more = show at most that many inline, the
    // rest go to the "+N" overflow popup.
    property int maxVisible: -1

    property bool overflowOpen: false
    onOverflowOpenChanged: {
        console.log("TRAYPOPDIAG overflowOpen=" + root.overflowOpen);
        if (!root.overflowOpen) overflowGrab.active = false;
    }

    // items is a Quickshell ObjectModel (a QAbstractListModel), not a JS
    // array: it has no length/slice. Read .values for array operations.
    readonly property var trayItems: SystemTray.items.values
    readonly property int shownCount: root.maxVisible >= 0
        ? Math.min(root.maxVisible, trayItems.length) : trayItems.length
    readonly property int hiddenCount: Math.max(0, trayItems.length - shownCount)

    component TrayIcon: Item {
        id: icon
        required property var entry
        signal activated()
        implicitWidth: root.iconSize
        implicitHeight: root.iconSize

        Image {
            anchors.fill: parent
            source: icon.entry.icon
            sourceSize.width: root.iconSize
            sourceSize.height: root.iconSize
            fillMode: Image.PreserveAspectFit
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: function (mouse) {
                if (mouse.button === Qt.LeftButton) icon.entry.activate();
                else if (mouse.button === Qt.MiddleButton) icon.entry.secondaryActivate();
                else if (icon.entry.hasMenu) {
                    // Anchor the menu to the window the icon actually lives
                    // in: inline icons are in the bar window, overflow icons
                    // in the popup window.
                    var w = icon.Window.window;
                    var p = icon.mapToItem(null, 0, icon.height);
                    icon.entry.display(w, p.x, p.y);
                }
                icon.activated();
            }
        }
    }

    Repeater {
        model: root.trayItems.slice(0, root.shownCount)

        delegate: TrayIcon {
            required property var modelData
            entry: modelData
        }
    }

    // The popup's anchor is computed when it is shown. A resize or output
    // change moves the bar window without moving the popup, so close it
    // instead of leaving it stale at the old position; the inline cap can
    // also change with the width, which reshuffles the popup's contents.
    Connections {
        target: root.Window.window
        function onWidthChanged() { root.overflowOpen = false }
        function onHeightChanged() { root.overflowOpen = false }
    }
    onMaxVisibleChanged: root.overflowOpen = false

    Text {
        id: overflowChip
        visible: root.hiddenCount > 0
        text: "+" + root.hiddenCount
        color: Theme.fg
        font.pixelSize: Math.max(10, root.iconSize - 3)
        opacity: root.overflowOpen ? 1.0 : 0.7

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: {
                console.log("TRAYPOPDIAG chip-click hidden=" + root.hiddenCount + " open->" + (!root.overflowOpen));
                root.overflowOpen = !root.overflowOpen;
            }
        }
    }

    // Overflow popup as a real popup window. The bar window is only
    // bar-height, so an in-window popup would be cut off by the compositor;
    // PopupWindow gets its own surface placed relative to the chip and
    // slides/flips to stay on screen. grabFocus dismisses it on an outside
    // click; Escape or picking an item also closes it.
    PopupWindow {
        id: overflowPopup
        // Default anchor rect is the chip's bounds; anchor its bottom-right
        // corner and expand downward-left so the popup hugs the screen edge.
        anchor.item: overflowChip
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.Flip
        color: "transparent"
        implicitWidth: overflowRow.implicitWidth + 16
        implicitHeight: overflowRow.implicitHeight + 16
        visible: root.overflowOpen && root.hiddenCount > 0
        // grabFocus maps to an xdg_popup grab, which Hyprland refuses for a
        // popup whose parent is a layer-shell surface (the bar): the grab
        // fails and the compositor immediately dismisses the popup, so it
        // never appears. HyprlandFocusGrab below is the supported way to get
        // the same outside-click dismissal on Hyprland.
        grabFocus: false
        onVisibleChanged: console.log("TRAYPOPDIAG popup visible=" + visible)
        onClosed: {
            console.log("TRAYPOPDIAG popup closed");
            root.overflowOpen = false;
        }

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: Theme.surfaceVariant
            border.width: 1
            border.color: Theme.outline
            focus: true
            onVisibleChanged: if (visible) forceActiveFocus()
            Keys.onEscapePressed: root.overflowOpen = false

            Row {
                id: overflowRow
                anchors.centerIn: parent
                spacing: 8

                Repeater {
                    model: root.trayItems.slice(root.shownCount)

                    delegate: TrayIcon {
                        required property var modelData
                        entry: modelData
                        onActivated: root.overflowOpen = false
                    }
                }
            }
        }
    }

    // Outside-click dismissal and keyboard focus for the overflow popup via
    // hyprland_focus_grab_v1: while active the popup keeps keyboard focus
    // (Escape reaches its Keys handler) and a click anywhere outside the
    // listed windows clears the grab, which closes the popup.
    // Activation is deferred past the popup's mapping: activating in the
    // same instant the window is created races the surface reaching the
    // compositor, leaving the grab never active (no Escape, no outside
    // click). A compositor without the protocol just leaves the grab
    // inactive and the chip toggles the popup.
    HyprlandFocusGrab {
        id: overflowGrab
        windows: [overflowPopup]
        active: false
        onActiveChanged: console.log("TRAYPOPDIAG grab active=" + active)
        onCleared: {
            console.log("TRAYPOPDIAG grab cleared");
            root.overflowOpen = false;
        }
    }

    Connections {
        target: overflowPopup
        function onVisibleChanged() {
            if (overflowPopup.visible) grabActivate.restart();
        }
    }

    Timer {
        id: grabActivate
        interval: 50
        onTriggered: {
            overflowGrab.active = root.overflowOpen && overflowPopup.visible;
            console.log("TRAYPOPDIAG grab activate attempt, active=" + overflowGrab.active);
        }
    }
}
