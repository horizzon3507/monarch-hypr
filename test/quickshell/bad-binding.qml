import QtQuick
import Quickshell

// Loads fine, but a binding refers to a name that does not exist. Quickshell
// reports that only as a WARN at runtime, so the smoke test must flag it.
ShellRoot {
  PanelWindow {
    implicitHeight: 20
    anchors { top: true; left: true; right: true }
    Text { text: undefinedName }
  }
}
