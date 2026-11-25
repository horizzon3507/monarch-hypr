import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "ShellLogic.js" as Logic

// The desktop wallpaper: one Background-layer window per screen, drawn from
// ~/.config/monarch/current/wallpaper.json ({"path": absolute image path or "",
// "rev": integer}), which monarch-wallpaper-sync writes atomically whenever the
// wallpaper changes. `rev` goes into the image URL, so a new image and the same
// path with new content both reload. Missing state, an empty path or an image
// that cannot be decoded leave the plain theme background and nothing else.
Scope {
    id: root

    readonly property string path: Quickshell.env("MONARCH_WALLPAPER_STATE")
        || (Quickshell.env("HOME") + "/.config/monarch/current/wallpaper.json")

    property var state: Logic.parseWallpaperState("")

    FileView {
        path: root.path
        watchChanges: true
        printErrors: false
        onLoaded: root.state = Logic.parseWallpaperState(text())
        onLoadFailed: root.state = Logic.parseWallpaperState("")
        onFileChanged: reload()
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "monarch-wallpaper"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: Theme.bg
            // An empty input region: the wallpaper never takes clicks or focus.
            mask: Region {}

            readonly property string url: Logic.wallpaperUrl(root.state)

            Image {
                id: image
                anchors.fill: parent
                source: win.url
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                // Decode at the screen's size, not the picture's.
                sourceSize: Qt.size(win.width * win.screen.devicePixelRatio, win.height * win.screen.devicePixelRatio)
                visible: status === Image.Ready
                onStatusChanged: console.log("monarch-shell wallpaper screen=" + win.screen.name
                    + " status=" + Logic.wallpaperStatus(win.url, status === Image.Ready, status === Image.Loading)
                    + " path=" + root.state.path)
            }
        }
    }
}
