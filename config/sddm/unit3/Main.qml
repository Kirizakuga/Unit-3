// Unit-3 style SDDM greeter, modelled on ~/.config/quickshell/widgets/lockscreen.qml
import QtQuick

Rectangle {
    id: root
    width: 1920; height: 1080
    color: "black"

    readonly property color ink:     config.stringValue("ink")     || "#463f2e"
    readonly property color inkSoft: config.stringValue("inkSoft") || "#7a7358"
    readonly property color paper:   config.stringValue("paper")   || "#d6cfb5"
    readonly property color curtain: config.stringValue("curtain") || "#c8b89a"
    readonly property color accent:  config.stringValue("accent")  || "#6e2a2a"

    // Pick the first installed mono font, so the theme still looks right without Share Tech Mono
    readonly property string mono: {
        var want = [config.stringValue("fontFamily"), "Share Tech Mono",
                    "ShureTechMono Nerd Font Mono", "ShureTechMono Nerd Font",
                    "JetBrains Mono", "DejaVu Sans Mono", "monospace"]
        var have = Qt.fontFamilies()
        for (var i = 0; i < want.length; i++)
            if (want[i] && have.indexOf(want[i]) !== -1) return want[i]
        return "monospace"
    }
    readonly property string jp: config.stringValue("jpFontFamily") || "Noto Sans CJK JP"

    // primaryScreen is provided by SDDM; the login panel only appears there
    readonly property bool isPrimary: typeof primaryScreen === "undefined" ? true : primaryScreen

    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property bool lockError: false
    property bool busy: false

    // Repeaters always instantiate, which gives us role values for each user/session
    Repeater { id: users; model: userModel; delegate: Item { property string uname: model.name } }
    Repeater { id: sessions; model: sessionModel; delegate: Item { property string sname: model.name } }
    readonly property string userName: {
        var it = users.count > 0 ? users.itemAt(userIndex) : null
        return it ? it.uname : (userModel.lastUser || "")
    }
    readonly property string sessionName: {
        var it = sessions.count > 0 ? sessions.itemAt(sessionIndex) : null
        return it ? it.sname : ""
    }

    function doAuth() {
        if (busy || userName === "") return
        busy = true
        lockError = false
        sddm.login(userName, pwInput.text, sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            root.lockError = true
            pwInput.text = ""
            shakeAnim.restart()
            pwInput.forceActiveFocus()
        }
        function onLoginSucceeded() { root.busy = false }
    }

    // Clock
    property string clockStr:  "--:--"
    property string dateStr:   "---- / -- / --"
    property string clockFull: "--:--:--"
    function tick() {
        var d = new Date(), p = function(x) { return String(x).padStart(2, "0") }
        clockStr  = p(d.getHours()) + ":" + p(d.getMinutes())
        clockFull = clockStr + ":" + p(d.getSeconds())
        dateStr   = d.getFullYear() + " / " + p(d.getMonth() + 1) + " / " + p(d.getDate())
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.tick() }

    Image {
        anchors.fill: parent
        source: config.stringValue("background") || "Assets/background.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
    }

    component Label: Text {
        font.family: root.mono; font.pixelSize: 9; font.letterSpacing: 2; color: root.ink
    }
    // Label with a paper backing so it stays readable on the grid background
    component Tag: Label {
        Rectangle { z: -1; color: root.paper; opacity: 0.9
            x: -4; y: -2; width: parent.contentWidth + 8; height: parent.height + 4
            anchors.right: parent.horizontalAlignment === Text.AlignRight ? parent.right : undefined
            anchors.rightMargin: -4 }
    }

    // Corners
    Column {
        anchors { top: parent.top; left: parent.left; topMargin: 28; leftMargin: 30 }
        spacing: 2
        Row { spacing: 5
            Rectangle { width: 5; height: 5; radius: 3; color: root.accent; anchors.verticalCenter: parent.verticalCenter
                SequentialAnimation on opacity { loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 900 } NumberAnimation { to: 1; duration: 900 } } }
            Tag { text: "AWAITING AUTHENTICATION" }
        }
        Tag { text: "NODE · " + (sddm.hostName || "localhost") }
        Text { text: "認証待機中"; font.family: root.jp; font.pixelSize: 8; color: root.ink; opacity: 0.7 }
    }
    Column {
        anchors { top: parent.top; right: parent.right; topMargin: 28; rightMargin: 30 }
        spacing: 2
        Tag { text: root.clockFull; width: 220; horizontalAlignment: Text.AlignRight }
        Tag { text: root.dateStr; width: 220; horizontalAlignment: Text.AlignRight }
    }

    // Bottom-left: session picker (click to cycle)
    Column {
        visible: root.isPrimary
        anchors { bottom: parent.bottom; left: parent.left; bottomMargin: 28; leftMargin: 30 }
        spacing: 2
        Tag { text: "SESSION ▸ " + root.sessionName.toUpperCase()
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: root.sessionIndex = (root.sessionIndex + 1) % Math.max(1, sessionModel.rowCount()) } }
        Tag { text: "WM · hyprland" }
    }

    // Bottom-right: power actions
    Row {
        visible: root.isPrimary
        anchors { bottom: parent.bottom; right: parent.right; bottomMargin: 24; rightMargin: 30 }
        spacing: 10
        Repeater {
            model: [
                { label: "SUSPEND",  ok: sddm.canSuspend },
                { label: "REBOOT",   ok: sddm.canReboot },
                { label: "SHUTDOWN", ok: sddm.canPowerOff }
            ]
            delegate: Rectangle {
                visible: modelData.ok
                width: btn.implicitWidth + 20; height: 22
                color: ma.containsMouse ? root.ink : "transparent"
                border.color: root.ink; border.width: 1
                Behavior on color { ColorAnimation { duration: 180 } }
                Label { id: btn; anchors.centerIn: parent; text: modelData.label; font.pixelSize: 8
                    color: ma.containsMouse ? root.paper : root.ink }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: index === 0 ? sddm.suspend() : index === 1 ? sddm.reboot() : sddm.powerOff() }
            }
        }
    }

    // Ticker
    Item {
        anchors { bottom: parent.bottom; bottomMargin: 65; left: parent.left; right: parent.right }
        height: 18; clip: true
        Label {
            id: tickTxt; y: 2; font.pixelSize: 8; font.letterSpacing: 3
            text: "SYSTEM SCAN · OK ▸ MEMORY INTEGRITY · VERIFIED ▸ AUTH DAEMON · LISTENING ▸ NETWORK UPLINK · STABLE ▸ THERMAL · NOMINAL ▸ AWAITING OPERATOR ▸ "
            NumberAnimation on x { from: root.width; to: -tickTxt.implicitWidth; duration: 55000; loops: Animation.Infinite }
        }
    }

    // Central panel
    Item {
        id: panelHost
        visible: root.isPrimary
        width: 380; height: panelRect.height
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -200
        opacity: 0

        Component.onCompleted: panelReveal.start()

        SequentialAnimation {
            id: panelReveal
            PauseAnimation { duration: 150 }
            ParallelAnimation {
                NumberAnimation { target: panelHost; property: "anchors.verticalCenterOffset"; to: 0; duration: 580; easing.type: Easing.OutExpo }
                NumberAnimation { target: panelHost; property: "opacity"; to: 1; duration: 320 }
            }
            NumberAnimation { target: wipeScale; property: "yScale"; to: 0; duration: 460; easing.type: Easing.OutExpo }
            ScriptAction { script: pwInput.forceActiveFocus() }
        }

        SequentialAnimation { id: shakeAnim
            NumberAnimation { target: panelHost; property: "anchors.horizontalCenterOffset"; from: 0; to: -10; duration: 55 }
            NumberAnimation { target: panelHost; property: "anchors.horizontalCenterOffset"; to: 10; duration: 75 }
            NumberAnimation { target: panelHost; property: "anchors.horizontalCenterOffset"; to: -7; duration: 65 }
            NumberAnimation { target: panelHost; property: "anchors.horizontalCenterOffset"; to: 7; duration: 65 }
            NumberAnimation { target: panelHost; property: "anchors.horizontalCenterOffset"; to: 0; duration: 55 }
        }

        Rectangle {
            id: panelRect
            width: 380; color: root.paper
            height: panelCol.implicitHeight + 72
            border.color: root.ink; border.width: 1

            Repeater { model: 20; Rectangle { x: index * 20; width: 1; height: panelRect.height; color: Qt.rgba(70/255, 63/255, 46/255, 0.06) } }
            Repeater { model: Math.ceil(panelRect.height / 20); Rectangle { y: index * 20; width: panelRect.width; height: 1; color: Qt.rgba(70/255, 63/255, 46/255, 0.06) } }

            // Scan line
            Rectangle {
                width: parent.width; height: 1; z: 20
                gradient: Gradient { orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: root.accent }
                    GradientStop { position: 1; color: "transparent" } }
                SequentialAnimation on y { loops: Animation.Infinite
                    NumberAnimation { from: 0; to: panelRect.height; duration: 3500 }
                    PauseAnimation { duration: 600 } }
            }

            Rectangle {
                anchors.fill: parent; color: root.curtain; z: 50
                transform: Scale { id: wipeScale; yScale: 1 }
            }

            Column {
                id: panelCol
                width: 308
                anchors { top: parent.top; topMargin: 36; horizontalCenter: parent.horizontalCenter }

                Item { width: parent.width; height: 90
                    Rectangle { width: 76; height: 76; border.color: root.ink; border.width: 1; color: "transparent"
                        anchors.horizontalCenter: parent.horizontalCenter
                        Rectangle { width: 52; height: 52; color: root.ink; anchors.centerIn: parent
                            transform: Rotation { angle: 45; origin.x: 26; origin.y: 26 } }
                        Label { text: "NR"; font.pixelSize: 7; font.letterSpacing: 0; color: root.inkSoft; opacity: 0.5
                            anchors { top: parent.top; left: parent.left; margins: 3 } }
                        Label { text: "2B"; font.pixelSize: 7; font.letterSpacing: 0; color: root.inkSoft; opacity: 0.5
                            anchors { bottom: parent.bottom; right: parent.right; margins: 3 } }
                    }
                }

                // Username (click to cycle users when there are several)
                Label {
                    text: root.userName.toUpperCase() + (userModel.count > 1 ? "  ⇄" : "")
                    font.pixelSize: 13; font.letterSpacing: 3
                    anchors.horizontalCenter: parent.horizontalCenter
                    MouseArea { anchors.fill: parent; enabled: userModel.count > 1; cursorShape: Qt.PointingHandCursor
                        onClicked: root.userIndex = (root.userIndex + 1) % userModel.count }
                }
                Item { width: 1; height: 4 }
                Text { text: "ユニット · スタンバイ"; font.family: root.jp; font.pixelSize: 8; color: root.inkSoft
                    anchors.horizontalCenter: parent.horizontalCenter }
                Item { width: 1; height: 20 }
                Label { text: root.clockStr; font.pixelSize: 46; anchors.horizontalCenter: parent.horizontalCenter }
                Item { width: 1; height: 6 }
                Label { text: root.dateStr; font.letterSpacing: 3; color: root.inkSoft; anchors.horizontalCenter: parent.horizontalCenter }
                Item { width: 1; height: 20 }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(70/255, 63/255, 46/255, 0.22) }
                Item { width: 1; height: 22 }

                Item { width: parent.width; height: 40
                    Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1
                        border.color: pwInput.activeFocus ? root.ink : Qt.rgba(70/255, 63/255, 46/255, 0.22)
                        Behavior on border.color { ColorAnimation { duration: 200 } } }
                    Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: "▸"; font.pixelSize: 10; color: root.accent }
                    TextInput {
                        id: pwInput
                        anchors { fill: parent; leftMargin: 26; rightMargin: 10 }
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: root.mono; font.pixelSize: 12; font.letterSpacing: 2
                        color: root.ink; echoMode: TextInput.Password; passwordCharacter: "·"
                        focus: true; clip: true
                        onTextEdited: root.lockError = false
                        Keys.onReturnPressed: root.doAuth()
                        Keys.onEnterPressed: root.doAuth()
                        Keys.onEscapePressed: text = ""
                        Text { visible: parent.text === ""; anchors.verticalCenter: parent.verticalCenter
                            text: "password..."; font.family: root.mono; font.pixelSize: 11; font.italic: true
                            color: root.inkSoft; opacity: 0.5 }
                    }
                }
                Item { width: 1; height: 8 }

                Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 6
                    Repeater { model: 6; Rectangle { width: 6; height: 6; color: "transparent"; border.color: root.inkSoft; border.width: 1
                        Rectangle { visible: index < pwInput.text.length; anchors.fill: parent; color: root.ink } } } }
                Item { width: 1; height: 6 }

                Label { text: "AUTHENTICATION FAILED"; font.pixelSize: 8; color: root.accent
                    anchors.horizontalCenter: parent.horizontalCenter; height: 14
                    opacity: root.lockError ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 200 } } }
                Item { width: 1; height: 10 }

                Item { width: parent.width; height: 42
                    Rectangle { anchors.fill: parent; color: "transparent"; border.color: root.ink; border.width: 1 }
                    Rectangle { id: fill; anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        color: root.ink; width: (loginMA.containsMouse || root.busy) ? parent.width : 0
                        Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.InOutQuart } } }
                    Label { anchors.centerIn: parent; text: root.busy ? "AUTHENTICATING" : "LOGIN"
                        font.pixelSize: 10; font.letterSpacing: 3
                        color: (loginMA.containsMouse || root.busy) ? root.paper : root.ink
                        Behavior on color { ColorAnimation { duration: 200 } } }
                    MouseArea { id: loginMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.doAuth() }
                }
            }
        }
    }
}
