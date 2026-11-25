import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// ═════════════════════════════════════════════════════════════════════
//   Unit-3 Alt+Tab — window switcher with live previews (Windows-style)
//   Alt+Tab / Alt+Shift+Tab  open and move   ·   release Alt  switch
//   ←/→ also move, Enter switches, Esc cancels, click a card to switch.
//   W / Q / Delete (or the × on a card) closes that window and keeps the switcher open.
//   IPC: qs ipc call alttab next|prev|commit|cancel
// ═════════════════════════════════════════════════════════════════════

Scope {
    id: root

    // ── Palette (same as the shell) ──
    readonly property color colBg:     Qt.rgba(11/255, 10/255, 9/255, 0.94)
    readonly property color colCard:   "#181613"
    readonly property color colLine:   "#2a2620"
    readonly property color colInk:    "#7a7358"
    readonly property color colSand:   "#c8b89a"
    readonly property color colDark:   "#0b0a09"
    readonly property string fontName: "JetBrains Mono"

    // ── Layout ──
    readonly property int thumbW: 300
    readonly property int thumbH: 180

    // ── State ──
    property bool   open: false
    property bool   loading: false
    property bool   commitWhenReady: false   // Alt released before the list arrived
    property string pendingDir: "next"
    property var    wins: []                 // [{address, title, cls, ws, toplevel}]
    property int    sel: 0
    property string monitorName: ""
    property int    currentWs: 1                 // where restored (minimized) windows go
    // hover only selects after the mouse really moves (a resting cursor must not steal the selection)
    property bool   hoverArmed: false
    onOpenChanged: { hoverArmed = false; if (open) armTimer.restart() }
    Timer { id: armTimer; interval: 250 }

    // load Hyprland's toplevel list at startup so previews are ready on first Alt+Tab
    Component.onCompleted: Hyprland.toplevels.values.length

    // ── Window list: hyprctl gives most-recently-used order and the focused monitor ──
    Process {
        id: listProc
        command: ["sh", "-c", "hyprctl clients -j; echo '@@SPLIT@@'; hyprctl monitors -j"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.build(this.text) }
    }

    function toplevelFor(address) {
        var bare = address.replace(/^0x/, "")
        var list = Hyprland.toplevels.values
        for (var i = 0; i < list.length; i++) {
            var a = String(list[i].address).replace(/^0x/, "")
            if (a === bare) return list[i].wayland
        }
        return null
    }

    function build(text) {
        loading = false
        var parts = text.split("@@SPLIT@@")
        var clients = [], monitors = []
        try { clients = JSON.parse(parts[0]); monitors = JSON.parse(parts[1]) } catch (e) { return }
        var focusedMon = monitors.filter(function(m){ return m.focused })[0]
        monitorName = focusedMon ? focusedMon.name : (monitors[0] ? monitors[0].name : "")
        currentWs = focusedMon ? focusedMon.activeWorkspace.id : 1

        // normal workspaces plus minimized windows (other special ones, like the Spotify scratchpad, are left out)
        var list = clients.filter(function(c){
            return c.mapped && !c.hidden && (c.workspace.id > 0 || c.workspace.name === "special:minimized")
        })
        list.sort(function(a, b){ return a.focusHistoryID - b.focusHistoryID })
        wins = list.map(function(c){
            return { address: c.address, title: c.title || c.class, cls: c.class || "",
                     ws: c.workspace.name, minimized: c.workspace.name === "special:minimized" }
        })
        if (wins.length === 0) { commitWhenReady = false; return }

        sel = pendingDir === "prev" ? wins.length - 1 : (wins.length > 1 ? 1 : 0)
        if (commitWhenReady) { commitWhenReady = false; focusSelected(); return }
        open = true
    }

    // ── Actions ──
    Process { id: focusProc; running: false }
    function focusSelected() {
        var w = wins[sel]
        if (!w) return
        var focus = "hyprctl dispatch 'hl.dsp.focus({window = \"address:" + w.address + "\"})'"
        // a minimized window comes back to the workspace you're on first
        var restore = w.minimized
            ? "hyprctl dispatch 'hl.dsp.window.move({window = \"address:" + w.address
              + "\", workspace = \"" + currentWs + "\"})' && "
            : ""
        focusProc.command = ["sh", "-c", restore + focus]
        focusProc.running = true
    }
    function start(dir) {
        if (open) {
            var n = wins.length
            sel = dir === "prev" ? (sel - 1 + n) % n : (sel + 1) % n
            return
        }
        if (loading) return
        pendingDir = dir
        loading = true
        listProc.running = true
    }
    function commit() {
        if (loading) { commitWhenReady = true; return }
        if (!open) return
        open = false
        focusSelected()
    }
    function cancel() { open = false; loading = false; commitWhenReady = false }

    // Close a window but keep switching: drop it from the list right away, then
    // re-read the list (an app may refuse or ask to confirm, e.g. unsaved work).
    Process { id: closeProc; running: false }
    function closeAt(i) {
        var w = wins[i]
        if (!w) return
        closeProc.command = ["hyprctl", "dispatch",
                             'hl.dsp.window.close({window = "address:' + w.address + '"})']
        closeProc.running = true
        var rest = wins.slice(); rest.splice(i, 1)
        wins = rest
        if (wins.length === 0) { open = false; return }
        if (sel >= wins.length) sel = wins.length - 1
        refreshTimer.restart()
    }
    Timer { id: refreshTimer; interval: 400; onTriggered: if (root.open) refreshProc.running = true }
    Process {
        id: refreshProc
        command: ["hyprctl", "clients", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var live = []
                try { live = JSON.parse(this.text).map(function(c){ return c.address }) } catch (e) { return }
                // keep our order and selection; just drop windows that are really gone
                var keep = root.wins.filter(function(w){ return live.indexOf(w.address) >= 0 })
                if (keep.length !== root.wins.length) {
                    root.wins = keep
                    if (root.sel >= keep.length) root.sel = Math.max(0, keep.length - 1)
                    if (keep.length === 0) root.open = false
                }
            }
        }
    }

    IpcHandler {
        target: "alttab"
        function next(): void   { root.start("next") }
        function prev(): void   { root.start("prev") }
        function commit(): void { root.commit() }
        function cancel(): void { root.cancel() }
        function close(): void  { root.closeAt(root.sel) }
        // for scripts/tests: "<selected index>/<count> <title>"
        function current(): string {
            var w = root.wins[root.sel]
            return root.open ? root.sel + "/" + root.wins.length + " " + (w ? w.title : "") : "closed"
        }
    }

    // ── Switcher window (on the focused monitor only) ──
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            visible: root.open && modelData.name === root.monitorName
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "unit3-alttab"
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // dim the desktop a little
            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35) }

            // click outside the panel cancels; moving the mouse (after a moment) enables hover-select
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.cancel()
                onPositionChanged: if (!armTimer.running) root.hoverArmed = true
            }

            Item {
                id: keys
                focus: true
                anchors.fill: parent
                Keys.onPressed: function(e) {
                    if (e.key === Qt.Key_Tab || e.key === Qt.Key_Right)        { root.start("next"); e.accepted = true }
                    else if (e.key === Qt.Key_Backtab || e.key === Qt.Key_Left) { root.start("prev"); e.accepted = true }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.commit(); e.accepted = true }
                    else if (e.key === Qt.Key_Escape)                           { root.cancel(); e.accepted = true }
                    else if (e.key === Qt.Key_W || e.key === Qt.Key_Q || e.key === Qt.Key_Delete)
                                                                                { root.closeAt(root.sel); e.accepted = true }
                }
                // releasing Alt switches (also handled by a Hyprland release bind)
                Keys.onReleased: function(e) {
                    if (e.key === Qt.Key_Alt) { root.commit(); e.accepted = true }
                }
            }
            onVisibleChanged: if (visible) keys.forceActiveFocus()

            // ── Panel ──
            Rectangle {
                id: box
                anchors.centerIn: parent
                width: flow.width + 48
                height: flow.childrenRect.height + 48 + header.height
                color: root.colBg
                border.color: root.colLine
                border.width: 1

                // L-corners like the Control Center cards
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
                    x: 24; y: 14; height: 24
                    text: "WINDOWS · " + root.wins.length + "      TAB next · W close · ESC cancel"
                    font.family: root.fontName; font.pixelSize: 10; font.letterSpacing: 3
                    color: root.colInk
                }

                Flow {
                    id: flow
                    x: 24; y: header.y + header.height + 6
                    width: Math.min(implicitWidthFull, panel.width * 0.9)
                    spacing: 14
                    readonly property int implicitWidthFull: root.wins.length * (root.thumbW + 14) - 14

                    Repeater {
                        model: root.wins
                        Item {
                            id: card
                            required property var modelData
                            required property int index
                            readonly property bool isSel: index === root.sel
                            // looked up reactively: Hyprland's toplevel list can fill in after we open
                            readonly property var toplevel: root.toplevelFor(modelData.address)
                            width: root.thumbW
                            height: root.thumbH + 34

                            Rectangle {
                                anchors.fill: parent
                                color: card.isSel ? Qt.rgba(200/255, 184/255, 154/255, 0.10) : "transparent"
                                border.color: card.isSel ? root.colSand : root.colLine
                                border.width: card.isSel ? 2 : 1
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                            }

                            // live preview, letterboxed to keep the window's shape
                            Rectangle {
                                id: thumbBox
                                x: 6; y: 6
                                width: parent.width - 12
                                height: root.thumbH - 6
                                color: root.colCard
                                clip: true
                                ScreencopyView {
                                    id: shot
                                    anchors.centerIn: parent
                                    captureSource: root.open ? card.toplevel : null
                                    live: true
                                    readonly property real ar: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16/9
                                    width:  Math.min(thumbBox.width, thumbBox.height * ar)
                                    height: Math.min(thumbBox.height, thumbBox.width / ar)
                                }
                                // fallback when there is no preview (e.g. window never shown yet)
                                Image {
                                    anchors.centerIn: parent
                                    visible: !shot.hasContent
                                    width: 56; height: 56
                                    sourceSize: Qt.size(56, 56)
                                    source: Quickshell.iconPath(card.modelData.cls.toLowerCase(), "application-x-executable")
                                }
                            }

                            // title bar: icon, title, workspace
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 2 }
                                height: 28
                                color: card.isSel ? root.colSand : "transparent"
                                Image {
                                    id: icon
                                    x: 6; anchors.verticalCenter: parent.verticalCenter
                                    width: 16; height: 16; sourceSize: Qt.size(16, 16)
                                    source: Quickshell.iconPath(card.modelData.cls.toLowerCase(), "application-x-executable")
                                }
                                Text {
                                    anchors { left: icon.right; leftMargin: 8; right: wsTag.left; rightMargin: 8
                                              verticalCenter: parent.verticalCenter }
                                    text: card.modelData.title
                                    elide: Text.ElideRight
                                    font.family: root.fontName; font.pixelSize: 11
                                    color: card.isSel ? root.colDark : root.colSand
                                }
                                Text {
                                    id: wsTag
                                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    text: card.modelData.minimized ? "MIN" : "WS " + card.modelData.ws
                                    font.family: root.fontName; font.pixelSize: 9; font.letterSpacing: 1.5
                                    color: card.isSel ? root.colDark : root.colInk
                                }
                            }

                            MouseArea {
                                id: cardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onPositionChanged: if (root.hoverArmed) root.sel = card.index
                                onClicked: { root.sel = card.index; root.commit() }
                            }

                            // × close button: shown on the selected or hovered card
                            Rectangle {
                                id: closeBtn
                                width: 26; height: 26
                                anchors { top: parent.top; right: parent.right; topMargin: 10; rightMargin: 10 }
                                visible: card.isSel || cardMouse.containsMouse || closeMouse.containsMouse
                                color: closeMouse.containsMouse ? "#6e2a2a" : root.colBg
                                border.color: closeMouse.containsMouse ? "#c87060" : root.colSand
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    font.family: root.fontName; font.pixelSize: 16
                                    color: root.colSand
                                }
                                MouseArea {
                                    id: closeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.closeAt(card.index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
