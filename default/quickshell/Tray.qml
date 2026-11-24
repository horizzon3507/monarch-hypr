import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray

// Status notifier icons. Left click activates, right click opens the item menu,
// middle click does the secondary action.
RowLayout {
    id: root
    spacing: 8
    property int iconSize: 16

    Repeater {
        model: SystemTray.items

        delegate: Item {
            id: entry
            required property var modelData
            implicitWidth: root.iconSize
            implicitHeight: root.iconSize

            Image {
                anchors.fill: parent
                source: entry.modelData.icon
                sourceSize.width: root.iconSize
                sourceSize.height: root.iconSize
                fillMode: Image.PreserveAspectFit
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: function (mouse) {
                    if (mouse.button === Qt.LeftButton) entry.modelData.activate();
                    else if (mouse.button === Qt.MiddleButton) entry.modelData.secondaryActivate();
                    else if (entry.modelData.hasMenu) {
                        var p = entry.mapToItem(null, 0, entry.height);
                        entry.modelData.display(root.Window.window, p.x, p.y);
                    }
                }
            }
        }
    }
}
