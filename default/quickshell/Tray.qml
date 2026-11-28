import QtQuick
import QtQuick.Layouts
import Quickshell
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

    readonly property var trayItems: SystemTray.items
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
            onClicked: root.overflowOpen = !root.overflowOpen
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
        grabFocus: root.overflowOpen
        onClosed: root.overflowOpen = false

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
}
