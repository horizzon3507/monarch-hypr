import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  Process {
    command: ["echo", "smoke-process"]
    running: true
    stdout: SplitParser {
      onRead: data => console.log("PROCESS " + data)
    }
  }

  PanelWindow {
    anchors { top: true; left: true; right: true }
    implicitHeight: 30
    Rectangle { anchors.fill: parent; color: "#7e33ff" }
  }

  Component.onCompleted: console.log("SMOKE-LOADED")
}

# probe actions trigger
