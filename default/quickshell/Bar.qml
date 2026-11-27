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

        Workspaces {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            fontSize: bar.fontSize
        }

        // The right group is anchored to the bar edge on its own, so it hugs the
        // right margin whatever its content (empty services take no space).
        RowLayout {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Tray { iconSize: Math.round(bar.fontSize * 1.2) }
            Connectivity {
                fontSize: bar.fontSize
                Layout.leftMargin: implicitWidth > 0 ? 14 : 0
            }
            Indicators {
                fontSize: bar.fontSize
                Layout.leftMargin: implicitWidth > 0 ? 14 : 0
            }
            // Power button: opens the session panel (lock, suspend, restart,
            // shut down) instead of the terminal system menu.
            Text {
                text: "\u23FB"
                color: Theme.fg
                font.pixelSize: bar.fontSize + 1
                Layout.leftMargin: 14
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: Quickshell.execDetached(["monarch-panel", "toggle", "session"])
                }
            }
        }
    }
}
