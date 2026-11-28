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
        // Below ~420px it switches to time-only so the date cannot force the
        // side groups into nothing.
        Text {
            id: clockLabel
            anchors.centerIn: parent
            text: bar.width < 420
                ? Qt.formatDateTime(clock.date, "hh:mm")
                : Logic.clockText(clock.date)
            font.pixelSize: bar.fontSize
            color: Theme.fg
        }

        // Each side group may use at most the space between its bar edge and
        // the clock (minus margin and a gap), so a long workspace row or a
        // full tray can never cover the clock on narrow screens.
        readonly property int sideLimit: Math.max(0,
            Math.floor((bar.width - clockLabel.width) / 2) - 10 - 12)

        Workspaces {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            fontSize: bar.fontSize
            availableWidth: bar.sideLimit
        }

        // Power button: opens the session panel (lock, suspend, restart,
        // shut down) instead of the terminal system menu. Anchored to the
        // bar edge on its own so the bounded group can never clip it away.
        Text {
            id: powerButton
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "\u23FB"
            color: Theme.fg
            font.pixelSize: bar.fontSize + 1
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                onClicked: Quickshell.execDetached(["monarch-panel", "toggle", "session"])
            }
        }

        // Adaptive right side. Level 0 shows every readout; higher levels give
        // space back in a fixed order: compact the wifi readout, compact the
        // indicators to chips + battery, hide the wifi readout, then cap the
        // tray behind an explicit "+N" overflow chip. Battery and state chips
        // (including the recording privacy chip) stay visible in every level;
        // the power button is anchored outside the group and can never be
        // clipped away. Widths come from hidden measurement copies
        // (Connectivity spawns no processes) or from parts that do not change
        // with the level, so there is no binding loop.
        readonly property int rightGrant: Math.max(0,
            bar.sideLimit - powerButton.width - 14)
        readonly property int trayIconStep: Math.round(fontSize * 1.2) + 8
        readonly property int rightLevel: computeRightLevel()

        function groupNeed(parts) {
            var w = 0, n = 0;
            for (var i = 0; i < parts.length; i++)
                if (parts[i] > 0) { w += parts[i]; n++; }
            return n === 0 ? 0 : w + (n - 1) * 14;
        }

        function computeRightLevel() {
            var trayW = trayRow.trayItems.length > 0
                ? trayRow.trayItems.length * trayIconStep - 8 : 0;
            var connF = connMeasureFull.implicitWidth;
            var connC = connMeasureCompact.implicitWidth;
            var indF = indicatorsRow.fullWidth;
            var indC = indicatorsRow.compactWidth;
            if (groupNeed([trayW, connF, indF]) <= rightGrant) return 0;
            if (groupNeed([trayW, connC, indF]) <= rightGrant) return 1;
            if (groupNeed([trayW, connC, indC]) <= rightGrant) return 2;
            if (groupNeed([trayW, 0, indC]) <= rightGrant) return 3;
            return 4;
        }

        Connectivity { id: connMeasureFull; visible: false; fontSize: bar.fontSize }
        Connectivity { id: connMeasureCompact; visible: false; compact: true; fontSize: bar.fontSize }

        // The right group is anchored to the power button, so it hugs the
        // right margin whatever its content (empty services take no space).
        // Hard-capped at rightGrant as a safety net behind the level logic.
        RowLayout {
            anchors.right: powerButton.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            width: Math.min(implicitWidth, bar.rightGrant)
            clip: true

            Tray {
                id: trayRow
                iconSize: Math.round(bar.fontSize * 1.2)
                maxVisible: bar.rightLevel >= 4
                    ? Math.max(0, Math.floor((bar.rightGrant - indicatorsRow.compactWidth - 14 - 24) / bar.trayIconStep))
                    : -1
            }
            Connectivity {
                fontSize: bar.fontSize
                compact: bar.rightLevel === 1 || bar.rightLevel === 2
                visible: bar.rightLevel <= 2
                Layout.leftMargin: implicitWidth > 0 ? 14 : 0
            }
            Indicators {
                id: indicatorsRow
                fontSize: bar.fontSize
                compact: bar.rightLevel >= 2
                Layout.leftMargin: implicitWidth > 0 ? 14 : 0
            }
        }
    }
}
