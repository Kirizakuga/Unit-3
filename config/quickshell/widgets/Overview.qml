import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// ═════════════════════════════════════════════════════════════════════
//   Unit-3 workspace overview — SUPER+A (or: qs ipc call overview toggle)
//   Every workspace in use, drawn to its screen's shape, with live window
//   previews at their real positions.
//   Click a window → focus it · click a tile → go there
//   ←→↑↓ move · Enter go · 1…0 jump · Esc close
// ═════════════════════════════════════════════════════════════════════

Scope {
    id: root

    readonly property color colBg:   Qt.rgba(11/255, 10/255, 9/255, 0.95)
    readonly property color colTile: "#12110f"
    readonly property color colLine: "#2a2620"
    readonly property color colInk:  "#7a7358"
    readonly property color colSand: "#c8b89a"
    readonly property color colDark: "#0b0a09"
    readonly property string fontName: "JetBrains Mono"

    property bool open: false
    property string monitorName: ""
    property var tiles: []      // [{id, name, mon:{w,h}, active, wins:[{address, cls, title, x, y, w, h}]}]
    property int sel: 0
    property int cols: 3

    // load Hyprland's toplevel list early so previews are ready on first open
    Component.onCompleted: Hyprland.toplevels.values.length

    Process {
        id: fetch
        command: ["sh", "-c", "hyprctl clients -j; echo '@@'; hyprctl monitors -j; echo '@@'; hyprctl workspaces -j"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.build(this.text) }
    }

    function toplevelFor(address) {
        var bare = address.replace(/^0x/, "")
        var list = Hyprland.toplevels.values
        for (var i = 0; i < list.length; i++)
            if (String(list[i].address).replace(/^0x/, "") === bare) return list[i].wayland
        return null
    }

    function build(text) {
        var p = text.split("@@"), clients = [], monitors = [], workspaces = []
        try { clients = JSON.parse(p[0]); monitors = JSON.parse(p[1]); workspaces = JSON.parse(p[2]) } catch (e) { return }
        var mons = {}
        monitors.forEach(function(m){ mons[m.name] = m })
        var fm = monitors.filter(function(m){ return m.focused })[0]
        monitorName = fm ? fm.name : (monitors[0] ? monitors[0].name : "")
        var visible = monitors.map(function(m){ return m.activeWorkspace.id })

        var list = workspaces.filter(function(w){ return w.id > 0 && (w.windows > 0 || visible.indexOf(w.id) >= 0) })
        list.sort(function(a, b){ return a.id - b.id })
        tiles = list.map(function(w){
            var m = mons[w.monitor] || fm
            var wins = clients.filter(function(c){ return c.workspace.id === w.id && c.mapped && !c.hidden })
                              .map(function(c){
                return { address: c.address, cls: c.class || "", title: c.title || c.class || "",
                         x: c.at[0] - m.x, y: c.at[1] - m.y, w: c.size[0], h: c.size[1],
                         floating: c.floating }
            })
            // floating windows on top, like on screen
            wins.sort(function(a, b){ return (a.floating ? 1 : 0) - (b.floating ? 1 : 0) })
            return { id: w.id, name: w.name, monitor: w.monitor, active: visible.indexOf(w.id) >= 0,
                     focused: fm && fm.activeWorkspace.id === w.id,
                     mon: { w: m.width / m.scale, h: m.height / m.scale }, wins: wins }
        })
        cols = tiles.length <= 4 ? Math.max(1, tiles.length) : (tiles.length <= 6 ? 3 : 4)
        sel = 0
        for (var i = 0; i < tiles.length; i++) if (tiles[i].focused) sel = i
        open = true
    }

    Process { id: act; running: false }
    function goWorkspace(id) {
        open = false
        act.command = ["hyprctl", "dispatch", 'hl.dsp.focus({workspace = "' + id + '"})']
        act.running = true
    }
    function goWindow(address) {
        open = false
        act.command = ["hyprctl", "dispatch", 'hl.dsp.focus({window = "address:' + address + '"})']
        act.running = true
    }
    function move(dx, dy) {
        if (tiles.length === 0) return
        var n = sel + dx + dy * cols
        if (n >= 0 && n < tiles.length) sel = n
    }
    function toggle() { if (open) open = false; else fetch.running = true }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.toggle() }
        function hide(): void   { root.open = false }
        // for scripts/tests: "<selected workspace> | <workspace>:<windows> …"
        function current(): string {
            if (!root.open) return "closed"
            var t = root.tiles[root.sel]
            return "selected " + (t ? t.name : "-") + " | "
                + root.tiles.map(function(x){ return x.name + ":" + x.wins.length + (x.focused ? "*" : "") }).join(" ")
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.open && modelData.name === root.monitorName
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "unit3-overview"
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.55) }
            MouseArea { anchors.fill: parent; onClicked: root.open = false }

            Item {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onPressed: function(e) {
                    if (e.key === Qt.Key_Escape)      { root.open = false; e.accepted = true }
                    else if (e.key === Qt.Key_Left)   { root.move(-1, 0); e.accepted = true }
                    else if (e.key === Qt.Key_Right)  { root.move(1, 0);  e.accepted = true }
                    else if (e.key === Qt.Key_Up)     { root.move(0, -1); e.accepted = true }
                    else if (e.key === Qt.Key_Down)   { root.move(0, 1);  e.accepted = true }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        var t = root.tiles[root.sel]; if (t) root.goWorkspace(t.id); e.accepted = true
                    } else if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9) {
                        root.goWorkspace(e.key === Qt.Key_0 ? 10 : e.key - Qt.Key_0); e.accepted = true
                    }
                }
            }
            onVisibleChanged: if (visible) keys.forceActiveFocus()

            // tile size: fit the grid into ~86% of the screen
            readonly property int rows: Math.max(1, Math.ceil(root.tiles.length / root.cols))
            readonly property real gap: 22
            readonly property real tileW: Math.min((width * 0.86 - (root.cols - 1) * gap) / root.cols,
                                                   ((height * 0.78 - (rows - 1) * (gap + 26)) / rows) * 16 / 9)

            Rectangle {
                id: box
                anchors.centerIn: parent
                width: grid.width + 56
                height: grid.height + 84
                color: root.colBg
                border.color: root.colLine; border.width: 1

                Repeater {
                    model: 4
                    Item {
                        width: 10; height: 10; z: 2
                        x: (index % 2 === 0) ? -1 : box.width - 9
                        y: (index < 2) ? -1 : box.height - 9
                        Rectangle { width: 10; height: 2; color: root.colSand; y: index < 2 ? 0 : 8 }
                        Rectangle { width: 2; height: 10; color: root.colSand; x: index % 2 === 0 ? 0 : 8 }
                    }
                }
                Text {
                    id: header
                    x: 28; y: 18
                    text: "WORKSPACES · " + root.tiles.length
                    font.family: root.fontName; font.pixelSize: 11; font.letterSpacing: 4; color: root.colSand
                }
                Text {
                    anchors { right: parent.right; rightMargin: 28; verticalCenter: header.verticalCenter }
                    text: "CLICK window · ←→↑↓ + ENTER · 1…0 · ESC"
                    font.family: root.fontName; font.pixelSize: 9; font.letterSpacing: 1.5; color: root.colInk
                }

                Grid {
                    id: grid
                    x: 28; y: 52
                    columns: root.cols
                    spacing: win.gap
                    Repeater {
                        model: root.tiles
                        Column {
                            id: tileCol
                            required property var modelData
                            required property int index
                            readonly property bool isSel: index === root.sel
                            readonly property real sc: win.tileW / modelData.mon.w
                            spacing: 6

                            // the workspace, drawn to its screen's shape
                            Rectangle {
                                id: tile
                                width: win.tileW
                                height: tileCol.modelData.mon.h * tileCol.sc
                                color: root.colTile
                                border.color: tileCol.isSel ? root.colSand : (tileCol.modelData.focused ? root.colInk : root.colLine)
                                border.width: tileCol.isSel ? 2 : 1
                                clip: true

                                MouseArea {
                                    anchors.fill: parent; hoverEnabled: true
                                    onEntered: root.sel = tileCol.index
                                    onClicked: root.goWorkspace(tileCol.modelData.id)
                                }

                                Repeater {
                                    model: tileCol.modelData.wins
                                    Rectangle {
                                        id: wbox
                                        required property var modelData
                                        readonly property var toplevel: root.toplevelFor(modelData.address)
                                        x: modelData.x * tileCol.sc; y: modelData.y * tileCol.sc
                                        width: Math.max(8, modelData.w * tileCol.sc); height: Math.max(8, modelData.h * tileCol.sc)
                                        color: "#181613"
                                        border.color: wMouse.containsMouse ? root.colSand : root.colLine
                                        border.width: 1
                                        clip: true
                                        ScreencopyView {
                                            id: shot
                                            anchors.fill: parent; anchors.margins: 1
                                            captureSource: root.open ? wbox.toplevel : null
                                            live: true
                                        }
                                        Image {
                                            anchors.centerIn: parent
                                            visible: !shot.hasContent
                                            width: Math.min(32, parent.width * 0.5); height: width
                                            sourceSize: Qt.size(32, 32)
                                            source: Quickshell.iconPath(wbox.modelData.cls.toLowerCase(), "application-x-executable")
                                        }
                                        MouseArea {
                                            id: wMouse
                                            anchors.fill: parent; hoverEnabled: true
                                            onEntered: root.sel = tileCol.index
                                            onClicked: root.goWindow(wbox.modelData.address)
                                        }
                                    }
                                }
                            }
                            // label
                            Row {
                                spacing: 8
                                Rectangle {
                                    width: numText.implicitWidth + 12; height: 18
                                    color: tileCol.isSel ? root.colSand : "transparent"
                                    border.color: root.colSand; border.width: 1
                                    Text {
                                        id: numText
                                        anchors.centerIn: parent
                                        text: tileCol.modelData.name
                                        font.family: root.fontName; font.pixelSize: 10
                                        color: tileCol.isSel ? root.colDark : root.colSand
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tileCol.modelData.wins.length + (tileCol.modelData.wins.length === 1 ? " window" : " windows")
                                          + (tileCol.modelData.focused ? " · here" : "") + " · " + tileCol.modelData.monitor
                                    font.family: root.fontName; font.pixelSize: 9; font.letterSpacing: 1; color: root.colInk
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
