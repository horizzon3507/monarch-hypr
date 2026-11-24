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

    Repeater {
        model: Logic.workspaceSlots(root.ids())

        delegate: Rectangle {
            id: slot
            required property int modelData
            readonly property var ws: root.find(modelData)
            readonly property bool focused: ws !== null && ws.focused
            readonly property bool urgent: ws !== null && ws.urgent

            implicitWidth: root.fontSize * 1.9
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
