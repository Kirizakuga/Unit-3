import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// ═════════════════════════════════════════════════════════════════════
//   Unit-3 shortcut cheat sheet — SUPER+/ (or: qs ipc call cheatsheet toggle)
//   Reads the live binds from Hyprland, so it never goes out of date.
//   Each bind's description is "Group · What it does"; binds that share a
//   description are merged (ALT+1 … ALT+0 → one row).
// ═════════════════════════════════════════════════════════════════════

Scope {
    id: root

    readonly property color colBg:   Qt.rgba(11/255, 10/255, 9/255, 0.95)
    readonly property color colLine: "#2a2620"
    readonly property color colInk:  "#7a7358"
    readonly property color colSand: "#c8b89a"
    readonly property color colDark: "#0b0a09"
    readonly property string fontName: "JetBrains Mono"
    readonly property var groupOrder: ["Windows", "Workspaces", "Apps", "Shell", "Media", "Screenshot", "Session", "Other"]

    property bool open: false
    property string monitorName: ""
    property var groups: []        // [{name, rows: [{keys, text}]}]

    Process {
        id: fetch
        command: ["sh", "-c", "hyprctl binds -j; echo '@@SPLIT@@'; hyprctl monitors -j"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.build(this.text) }
    }

    // ── key formatting ──
    function modNames(mask) {
        var out = []
        if (mask & 64) out.push("SUPER")
        if (mask & 4)  out.push("CTRL")
        if (mask & 8)  out.push("ALT")
        if (mask & 1)  out.push("SHIFT")
        return out
    }
    function keyName(k) {
        var map = { left: "←", right: "→", up: "↑", down: "↓", Return: "Enter", Escape: "Esc",
                    Tab: "Tab", Space: "Space", space: "Space", slash: "/", Print: "PrtSc",
                    "mouse:272": "LMB drag", "mouse:273": "RMB drag", mouse_down: "Wheel", mouse_up: "Wheel",
                    Super_L: "tap", XF86AudioRaiseVolume: "Vol +", XF86AudioLowerVolume: "Vol −",
                    XF86AudioMute: "Mute", XF86MonBrightnessUp: "Bright +", XF86MonBrightnessDown: "Bright −" }
        return map[k] !== undefined ? map[k] : (k.length === 1 ? k.toUpperCase() : k)
    }
    // ["1","2",…,"0"] → "1…0"; otherwise unique keys joined
    function joinKeys(keys) {
        var uniq = []
        for (var i = 0; i < keys.length; i++) if (uniq.indexOf(keys[i]) < 0) uniq.push(keys[i])
        var digits = uniq.every(function(k){ return /^[0-9]$/.test(k) })
        if (digits && uniq.length > 2) return uniq[0] + "…" + uniq[uniq.length - 1]
        return uniq.join(" ")
    }

    function build(text) {
        var parts = text.split("@@SPLIT@@"), binds = [], monitors = []
        try { binds = JSON.parse(parts[0]); monitors = JSON.parse(parts[1]) } catch (e) { return }
        var fm = monitors.filter(function(m){ return m.focused })[0]
        monitorName = fm ? fm.name : (monitors[0] ? monitors[0].name : "")

        // group rows by description (and modifiers), keeping config order
        var byDesc = {}, order = []
        for (var i = 0; i < binds.length; i++) {
            var b = binds[i]
            var desc = b.description || ""
            var group = "Other", label = desc
            var sep = desc.indexOf(" · ")
            if (sep > 0) { group = desc.substring(0, sep); label = desc.substring(sep + 3) }
            if (!desc) label = (b.dispatcher || "") + (b.arg ? " " + b.arg : "")
            var mods = modNames(b.modmask).join(" + ")
            var id = group + "|" + label + "|" + mods
            if (!byDesc[id]) { byDesc[id] = { group: group, text: label, mods: mods, keys: [] }; order.push(id) }
            byDesc[id].keys.push(keyName(b.key))
        }
        var g = {}
        for (var j = 0; j < order.length; j++) {
            var r = byDesc[order[j]]
            var keyStr = r.keys[0] === "tap" ? r.mods + " (tap)" : (r.mods ? r.mods + " + " : "") + joinKeys(r.keys)
            ;(g[r.group] = g[r.group] || []).push({ keys: keyStr, text: r.text })
        }
        var names = Object.keys(g).sort(function(a, b2) {
            var ia = groupOrder.indexOf(a), ib = groupOrder.indexOf(b2)
            return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib)
        })
        groups = names.map(function(n){ return { name: n, rows: g[n] } })
        open = true
    }

    function toggle() { if (open) open = false; else fetch.running = true }

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { root.toggle() }
        function hide(): void   { root.open = false }
        // for scripts/tests: "<groups>/<rows>"
        function current(): string {
            var rows = 0
            for (var i = 0; i < root.groups.length; i++) rows += root.groups[i].rows.length
            return root.open ? root.groups.length + " groups / " + rows + " rows" : "closed"
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
            WlrLayershell.namespace: "unit3-cheatsheet"
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45) }
            MouseArea { anchors.fill: parent; onClicked: root.open = false }

            Item {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onPressed: function(e) {
                    if (e.key === Qt.Key_Escape || e.key === Qt.Key_Slash || e.key === Qt.Key_Question
                        || e.key === Qt.Key_Return || e.key === Qt.Key_Q) { root.open = false; e.accepted = true }
                }
            }
            onVisibleChanged: if (visible) keys.forceActiveFocus()

            Rectangle {
                id: box
                anchors.centerIn: parent
                width: Math.min(win.width - 80, 1180)
                height: Math.min(win.height - 80, flow.childrenRect.height + 84)
                color: root.colBg
                border.color: root.colLine; border.width: 1
                clip: true

                // L-corners
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
                    text: "SHORTCUTS"
                    font.family: root.fontName; font.pixelSize: 11; font.letterSpacing: 4; color: root.colSand
                }
                Text {
                    anchors { right: parent.right; rightMargin: 28; verticalCenter: header.verticalCenter }
                    text: "ESC close · read live from Hyprland"
                    font.family: root.fontName; font.pixelSize: 9; font.letterSpacing: 1.5; color: root.colInk
                }

                Flickable {
                    x: 28; y: 52
                    width: box.width - 56; height: box.height - 70
                    contentHeight: flow.childrenRect.height
                    clip: true
                    Flow {
                        id: flow
                        width: parent.width
                        spacing: 22
                        Repeater {
                            model: root.groups
                            Column {
                                required property var modelData
                                width: (flow.width - 2 * flow.spacing) / 3
                                spacing: 7
                                Text {
                                    text: modelData.name.toUpperCase()
                                    font.family: root.fontName; font.pixelSize: 9; font.letterSpacing: 3
                                    color: root.colInk
                                }
                                Rectangle { width: parent.width; height: 1; color: root.colLine }
                                Repeater {
                                    model: modelData.rows
                                    Item {
                                        required property var modelData
                                        width: parent.width; height: Math.max(chip.height, label.implicitHeight)
                                        Rectangle {
                                            id: chip
                                            width: Math.min(chipText.implicitWidth + 12, parent.width * 0.52); height: 20
                                            color: "transparent"; border.color: root.colSand; border.width: 1
                                            Text {
                                                id: chipText
                                                anchors.centerIn: parent
                                                width: parent.width - 10
                                                horizontalAlignment: Text.AlignHCenter
                                                elide: Text.ElideRight
                                                text: modelData.keys
                                                font.family: root.fontName; font.pixelSize: 10; color: root.colSand
                                            }
                                        }
                                        Text {
                                            id: label
                                            anchors { left: chip.right; leftMargin: 10; right: parent.right
                                                      verticalCenter: chip.verticalCenter }
                                            text: modelData.text
                                            wrapMode: Text.WordWrap
                                            font.family: root.fontName; font.pixelSize: 11; color: "#e4dccb"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
