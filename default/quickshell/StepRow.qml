import QtQuick
import QtQuick.Layouts

// One label, a minus, a value and a plus on a fixed grid, so every row of a
// panel lines up in the same columns.
RowLayout {
    id: row
    property string label: ""
    property string valueText: ""
    property bool active: true
    signal stepped(int direction)

    spacing: 8
    Layout.alignment: Qt.AlignLeft

    Text {
        text: row.label
        color: Theme.fg
        opacity: 0.7
        font.pixelSize: 13
        Layout.preferredWidth: 80
    }
    Text {
        text: "\u2212"
        color: Theme.accent
        font.pixelSize: 18
        opacity: row.active ? 1.0 : 0.4
        Layout.preferredWidth: 20
        horizontalAlignment: Text.AlignHCenter
        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: row.stepped(-1) }
    }
    Text {
        text: row.valueText
        color: Theme.fg
        font.pixelSize: 13
        Layout.preferredWidth: 60
        horizontalAlignment: Text.AlignHCenter
    }
    Text {
        text: "+"
        color: Theme.accent
        font.pixelSize: 18
        opacity: row.active ? 1.0 : 0.4
        Layout.preferredWidth: 20
        horizontalAlignment: Text.AlignHCenter
        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: row.stepped(1) }
    }
}
