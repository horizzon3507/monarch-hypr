import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "ShellLogic.js" as Logic

// Workspace buttons from Hyprland. Slots 1-5 always show; the focused one is
// filled with the accent color, urgent ones use the error color.
RowLayout {
    id: root
    spacing: 4

    property int fontSize: 13
    // Width the bar grants this group, in px. 0 means unlimited (legacy
    // behavior for callers that do not know the available space).
    property int availableWidth: 0

    readonly property int slotWidth: Math.round(fontSize * 1.9)
    // How many slots fit the granted width. Zero when the grant fits not even
    // one slot: nothing renders rather than a slot spilling onto the clock.
    readonly property int maxSlots: availableWidth > 0
        ? (availableWidth >= slotWidth
            ? Math.max(1, Math.floor((availableWidth + spacing) / (slotWidth + spacing)))
            : 0)
        : 0

    function ids() {
        var out = [];
        for (var i = 0; i < Hyprland.workspaces.values.length; i++)
            out.push(Hyprland.workspaces.values[i].id);
        return out;
    }

    function find(id) {
        var list = Hyprland.workspaces.values;
        for (var i = 0; i < list.length; i++)
            if (list[i].id === id) return list[i];
        return null;
    }

    function focusedId() {
        var list = Hyprland.workspaces.values;
        for (var i = 0; i < list.length; i++)
            if (list[i].focused) return list[i].id;
        return -1;
    }

    // Slots that fit the granted width. A grant of 0 means unlimited (legacy
    // callers). A positive grant that fits nothing shows nothing. Otherwise
    // the focused workspace is always kept: if capping would drop it, it
    // replaces the highest shown slot.
    function visibleSlots() {
        var all = Logic.workspaceSlots(root.ids());
        if (root.availableWidth <= 0) return all;
        if (all.length <= root.maxSlots) return all;
        if (root.maxSlots <= 0) return [];
        var out = all.slice(0, root.maxSlots);
        var focus = root.focusedId();
        if (focus > 0 && out.indexOf(focus) < 0) {
            out[out.length - 1] = focus;
            out.sort(function (a, b) { return a - b; });
        }
        return out;
    }

    Repeater {
        model: root.visibleSlots()

        delegate: Rectangle {
            id: slot
            required property int modelData
            readonly property var ws: root.find(modelData)
            readonly property bool focused: ws !== null && ws.focused
            readonly property bool urgent: ws !== null && ws.urgent

            implicitWidth: root.slotWidth
            implicitHeight: root.fontSize * 1.7
            radius: 4
            color: focused ? Theme.accent : (urgent ? Theme.error : "transparent")
            border.width: focused || urgent ? 0 : 1
            border.color: ws !== null ? Theme.fg : Theme.outline

            Text {
                anchors.centerIn: parent
                text: slot.modelData
                font.pixelSize: root.fontSize
                color: slot.focused || slot.urgent ? Theme.bg : Theme.fg
                opacity: slot.focused || slot.urgent || slot.ws !== null ? 1.0 : 0.6
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    var request = Logic.workspaceDispatch(slot.modelData);
                    if (request !== "") Hyprland.dispatch(request);
                }
            }
        }
    }
}
