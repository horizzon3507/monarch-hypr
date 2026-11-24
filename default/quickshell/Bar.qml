import QtQuick
import QtQuick.Layouts
import Quickshell
import "ShellLogic.js" as Logic

// One bar per screen. Position, visibility and text size come from Settings.
Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
        id: bar
        required property var modelData
        screen: modelData

        readonly property int fontSize: Math.round(13 * Settings.textScale)

        visible: Settings.barVisible
        color: Theme.bg
        implicitHeight: Math.round(fontSize * 2.4)
        exclusiveZone: implicitHeight

        anchors {
            top: Settings.barPosition === "top"
            bottom: Settings.barPosition === "bottom"
            left: true
            right: true
        }

        SystemClock {
            id: clock
            precision: SystemClock.Minutes
        }

        // Centered on the bar itself, so the side widgets' widths do not move it.
        Text {
            anchors.centerIn: parent
            text: Logic.clockText(clock.date)
            font.pixelSize: bar.fontSize
            color: Theme.fg
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 14

            Workspaces {
                fontSize: bar.fontSize
            }

            Item { Layout.fillWidth: true }

            Tray { iconSize: Math.round(bar.fontSize * 1.2) }
            Indicators { fontSize: bar.fontSize }
        }
    }
}
