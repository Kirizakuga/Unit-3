import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

ShellRoot {
    id: root

    // ── Music (MPRIS): shown once something plays while locked; stays if paused from here ──
    // Reactive: re-evaluates the moment a player appears or starts/stops playing
    // (the player list fills in over D-Bus just after this process starts).
    readonly property var playingPlayer: {
        var ps = Mpris.players.values, first = null
        for (var i = 0; i < ps.length; i++) {
            if (!ps[i].isPlaying) continue
            if (ps[i].trackArtUrl) return ps[i]   // browsers can expose a track twice: prefer the entry with art
            if (!first) first = ps[i]
        }
        return first
    }
    property var  mprisPlayer: null
    property bool musicLatched: false
    onPlayingPlayerChanged: {
        if (playingPlayer) { mprisPlayer = playingPlayer; musicLatched = true }
        // nothing playing: keep the current one while it's still around (paused from here)
        else if (mprisPlayer && Mpris.players.values.indexOf(mprisPlayer) < 0) mprisPlayer = null
    }
    // MPRIS doesn't push playback position: ask for it once a second while playing
    Timer {
        interval: 1000; repeat: true
        running: !root.done && root.mprisPlayer !== null && root.mprisPlayer.isPlaying
        onTriggered: root.mprisPlayer.positionChanged()
    }
    // ── Cover art: player art → same track from another player → YouTube thumbnail → iTunes lookup ──
    // "(12) Song - YouTube" and "Song" are the same track
    function cleanTitle(t) {
        return String(t || "").replace(/^\(\d+\)\s*/, "").replace(/\s+-\s+YouTube( Music)?$/, "").trim().toLowerCase()
    }
    function youtubeId(url) {
        var m = String(url || "").match(/(?:[?&]v=|youtu\.be\/|\/shorts\/|\/embed\/)([A-Za-z0-9_-]{11})/)
        return m ? m[1] : ""
    }
    readonly property string directArt: {
        var p = mprisPlayer
        if (!p) return ""
        if (p.trackArtUrl) return p.trackArtUrl
        var ps = Mpris.players.values
        // browsers often expose the same track twice (e.g. Brave + plasma-browser-integration); one may have art
        for (var i = 0; i < ps.length; i++)
            if (ps[i] !== p && cleanTitle(ps[i].trackTitle) === cleanTitle(p.trackTitle) && ps[i].trackArtUrl) return ps[i].trackArtUrl
        var all = [p].concat(ps)
        for (var j = 0; j < all.length; j++) {
            if (j > 0 && cleanTitle(all[j].trackTitle) !== cleanTitle(p.trackTitle)) continue
            var id = youtubeId(all[j].metadata ? all[j].metadata["xesam:url"] : "")
            if (id) return "https://i.ytimg.com/vi/" + id + "/maxresdefault.jpg"
        }
        return ""
    }
    property string lookedUpArt: ""
    property string lookedUpFor: ""
    // not every YouTube video has a max-resolution thumbnail: fall back to the standard one
    property string failedArt: ""
    readonly property string coverUrl: {
        var u = directArt !== "" ? directArt : lookedUpArt
        return (u === failedArt && u.indexOf("maxresdefault") >= 0) ? u.replace("maxresdefault", "hqdefault") : u
    }
    // Last resort for players that send no art: look the track up in Apple's public iTunes catalog
    function maybeLookUpArt() {
        var p = mprisPlayer
        if (!p || directArt !== "" || !p.trackTitle) return
        var key = (p.trackArtist || "") + " " + p.trackTitle
        if (key === lookedUpFor) return
        lookedUpFor = key; lookedUpArt = ""
        artLookup.command = ["curl", "-s", "--max-time", "5",
            "https://itunes.apple.com/search?entity=song&limit=1&term=" + encodeURIComponent(key.trim())]
        artLookup.running = true
    }
    onDirectArtChanged: maybeLookUpArt()
    onMprisPlayerChanged: maybeLookUpArt()
    Connections {
        target: root.mprisPlayer
        ignoreUnknownSignals: true
        function onTrackTitleChanged() { root.maybeLookUpArt() }
    }
    Process {
        id: artLookup
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var r = JSON.parse(this.text).results
                    if (r && r.length && r[0].artworkUrl100)
                        root.lookedUpArt = r[0].artworkUrl100.replace("100x100bb", "600x600bb")
                } catch (e) {}
            }
        }
    }

    function fmtTime(sec) {
        if (!(sec > 0)) return "0:00"
        var s = Math.floor(sec % 60)
        return Math.floor(sec / 60) + ":" + (s < 10 ? "0" : "") + s
    }

    // ── Fast mode (skip reveal animation, used for lid-switch lock) ──
    property bool fastMode: Quickshell.env("UNIT3_LOCK_FAST") === "1"

    // ── Text with a cream backing, for readability over the grid ──
    component Tag: Text { font.family: "JetBrains Mono";
        Rectangle {
            z: -1; color: "#d6cfb5"; opacity: 0.92
            x: parent.horizontalAlignment === Text.AlignRight ? parent.width - parent.contentWidth - 5 : -5
            y: -2; width: parent.contentWidth + 10; height: parent.height + 4
        }
    }

    // ── État partagé ──
    property bool   revealing: false   // vidéo reveal en cours
    property bool   frozen:    false   // reveal freezée sur dernière frame
    property bool   hiding:    false   // vidéo hide en cours
    property bool   done:      false   // tout terminé

    // ── Paths génériques (portables) ──
    property string home:          Quickshell.env("HOME")
    property string xdgConfigHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")

    // ── Auth partagée ──
    property string lockInput:   ""
    property bool   lockError:   false
    property bool   lockPending: false

    property string currentUser: "user"
    property string kernel: ""

    // ── Battery (UPower) ──
    readonly property var bat: UPower.displayDevice
    readonly property bool hasBattery: bat.ready && bat.isLaptopBattery && bat.isPresent
    readonly property int batPct: Math.round(bat.percentage * 100)
    readonly property bool batLow: hasBattery && UPower.onBattery && batPct <= 20
    function fmtDur(sec) {
        var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60)
        return h > 0 ? h + "H " + m + "M" : m + "M"
    }
    readonly property string batText: {
        if (!hasBattery) return ""
        var t = "BAT " + batPct + "%"
        if (bat.state === UPowerDeviceState.Charging)          t += " · CHARGING"
        else if (bat.state === UPowerDeviceState.FullyCharged) t += " · FULL"
        else if (batLow)                                       t += " · LOW"
        else if (UPower.onBattery && bat.timeToEmpty > 0)      t += " · " + fmtDur(bat.timeToEmpty)
        return t
    }

    // ── Notifications that arrived while locked: a count only, never their content ──
    property int notifBase: -1
    property int notifNow: 0
    readonly property int newNotifs: notifBase < 0 ? 0 : Math.max(0, notifNow - notifBase)
    Process {
        id: notifPoll
        command: ["qs", "ipc", "call", "notifs", "getCount"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var n = parseInt(this.text.trim())
                if (isNaN(n)) return
                if (root.notifBase < 0 || n < root.notifBase) root.notifBase = n   // first read, or history trimmed
                root.notifNow = n
            }
        }
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: !root.done && !root.hiding
        onTriggered: if (!notifPoll.running) notifPoll.running = true
    }

    // ── Machine details, detected so the lockscreen fits whoever uses it ──
    property string hostName: ""
    property string sysTag: ""            // e.g. "CACHYOS · RTX 4050"
    // optional override of the shown machine name: "lock": {"node": "…"} in settings/user.json
    FileView {
        path: root.home + "/.config/quickshell/settings/user.json"
        blockLoading: true
        JsonAdapter {
            id: userCfg
            property JsonObject lock: JsonObject { property string node: "" }
        }
    }
    readonly property string node: userCfg.lock.node || hostName || "localhost"
    Process {
        command: ["sh", "-c", "cat /etc/hostname 2>/dev/null || uname -n"]; running: true
        stdout: SplitParser { onRead: data => { if (data.trim()) root.hostName = data.trim() } }
    }
    Process {
        // distro name, then one line per GPU from lspci (vendor | device)
        command: ["sh", "-c", ". /etc/os-release 2>/dev/null; echo \"OS|${NAME:-Linux}\"; "
                  + "lspci -mm 2>/dev/null | awk -F'\"' '$2 ~ /VGA|3D|Display/ {print \"GPU|\" $4 \"|\" $6}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var os = "LINUX", gpus = []
                this.text.split("\n").forEach(function(l) {
                    var f = l.split("|")
                    if (f[0] === "OS") os = f[1].replace(/ Linux$/, "").toUpperCase()
                    else if (f[0] === "GPU") gpus.push({ vendor: f[1], dev: f[2] })
                })
                // prefer a dedicated GPU (NVIDIA first), else whatever there is
                var g = gpus.filter(function(x){ return /NVIDIA/i.test(x.vendor) })[0] || gpus[gpus.length - 1]
                var name = ""
                if (g) {
                    var m = g.dev.match(/\[(.*)\]/)
                    name = (m ? m[1] : g.dev).replace(/^GeForce /, "").split(/ Max-Q| \/| Mobile| Laptop/)[0].trim()
                    if (!m && /AMD|ATI/i.test(g.vendor)) name = "AMD " + name
                    else if (!m && /Intel/i.test(g.vendor)) name = "INTEL " + name
                }
                root.sysTag = name ? os + " · " + name.toUpperCase() : os
            }
        }
    }
    Process {
        command:["uname","-r"]; running:true
        stdout: SplitParser { onRead: data => root.kernel = data.trim() }
    }
    Process {
        id: getUserProc; command:["sh","-c","echo $USER"]; running:true
        stdout: SplitParser { onRead: data => { var u=data.trim(); if(u!=="") root.currentUser=u } }
    }

    Process {
        id: authProc
        command:["/bin/bash","-c",
            "printf '%s\\n' \"$LOCKPWD\" | pamtester qs-lock \"$LOCKUSER\" authenticate >/dev/null 2>&1 && echo OK || echo FAIL"]
        running: false
        property string envPwd:""; property string envUser:""
        environment:({"LOCKPWD":authProc.envPwd,"LOCKUSER":authProc.envUser})
        stdout: StdioCollector { onStreamFinished: {
            root.lockPending = false
            if (this.text.trim() === "OK") {
                root.lockInput = ""
                root.lockError = false
                root.doHide()   // auth OK → lancer hide
            } else {
                root.lockError = true
                root.lockInput = ""
                errTimer.restart()
            }
        }}
    }
    Timer { id:errTimer; interval:800; repeat:false; onTriggered: root.lockError=false }

    function doAuth() {
        if (root.lockPending || root.lockInput === "") return
        root.lockPending = true
        authProc.envPwd  = root.lockInput
        authProc.envUser = root.currentUser
        authProc.running = true
    }

    // Password accepted: show the wipe overlays (same background, so nothing flashes),
    // then unlock the session underneath them and let the wave uncover the desktop.
    function doHide() {
        root.hiding = true
        unlockTimer.start()
    }
    Timer { id: unlockTimer; interval: 60; onTriggered: sessionLock.locked = false }

    // ── Gestion du curseur Hyprland ──
    // Le curseur natif Hyprland est conservé, rien à faire côté lockscreen.

    Component.onCompleted: {
        if (root.fastMode) {
            // Skip reveal animation entirely
            root.frozen = true
        } else {
            root.revealing = true
        }
    }

    // ── Real session lock (ext-session-lock) ──
    // While locked, Hyprland shows only these surfaces and gives them the keyboard. If this
    // process ever dies, the session stays locked; running the lock again takes it back over
    // (misc.allow_session_lock_restore in hypr/unit3.lua).
    WlSessionLock {
        id: sessionLock
        locked: true
        WlSessionLockSurface {
            color: "black"
            readonly property var modelData: screen   // the old per-screen window used modelData
            property bool isPrimary: screen !== null && screen.name === Quickshell.screens[0].name
            // the unlock wipe now plays in a separate overlay after the session unlocks
            readonly property bool hideStarted: false

            Rectangle { anchors.fill: parent; color: "black"; z: -1; visible: !root.hiding && !root.done }

            // ── Fast mode background ──
            // Affiche la dernière frame de wave_reveal.mp4 comme image statique.
            // Chargement instantané (pas de FFmpeg, pas de codec vidéo).
            Image {
                id: fastBg
                anchors.fill: parent
                source: root.fastMode ? ("file://" + root.xdgConfigHome + "/quickshell/videos/wave_last_frame.png") : ""
                visible: root.fastMode && !hideStarted && !root.done
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                cache: true
                z: 0
            }

            // ── Reveal ──
            MediaPlayer {
                id: reveal
                source: root.fastMode ? "" : ("file://" + root.xdgConfigHome + "/quickshell/videos/wave_reveal.mp4")
                videoOutput: voReveal
                audioOutput: null
                loops: 1
                autoPlay: false
                onPositionChanged: function() {
                    if (root.hiding || root.done) return
                    var pos = reveal.position
                    var dur = reveal.duration
                    if (dur > 0 && pos >= dur - 34) {
                        reveal.pause()
                        root.revealing = false
                    }
                }
            }
            VideoOutput {
                id: voReveal
                anchors.fill: parent
                visible: !root.fastMode && !hideStarted && !root.done
            }

            // ── UI Lockscreen ──
            Item {
                anchors.fill: parent
                visible: !root.done
                z: 2

                property real uiOp: ((root.frozen || root.revealing) ? 1 : 0) * hideOp
                Behavior on uiOp {
                    enabled: !root.fastMode && !root.hiding
                    NumberAnimation { duration: 400 }
                }
                // Corners and ticker (text + cream backing) fade out as the unlock wave starts
                property real hideOp: 1
                NumberAnimation on hideOp {
                    running: root.hiding; to: 0; duration: 450; easing.type: Easing.OutQuad
                }

                // Coins
                Item {
                    anchors { top:parent.top; left:parent.left; topMargin:28; leftMargin:30 }
                    z:5; opacity:parent.uiOp
                    Column { spacing:2
                        Row { spacing:5
                            Rectangle { width:5;height:5;radius:3;color:"#6e2a2a"
                                anchors.verticalCenter:parent.verticalCenter
                                SequentialAnimation on opacity { running:root.frozen; loops:Animation.Infinite
                                    NumberAnimation{to:0.3;duration:900} NumberAnimation{to:1;duration:900} }
                            }
                            Tag{text:"SESSION LOCKED";font.family: "JetBrains Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e"}
                        }
                        Tag{text:"NODE · "+root.currentUser+"@"+root.node;width:Math.min(implicitWidth,320);elide:Text.ElideRight;font.family: "JetBrains Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e"}
                        Tag{text:"セッションロック中";font.family: "JetBrains Mono";font.pixelSize:8;color:"#463f2e";opacity:0.7}
                    }
                }
                Item {
                    anchors { top:parent.top; right:parent.right; topMargin:28; rightMargin:30 }
                    z:5; opacity:parent.uiOp
                    Column { spacing:2; anchors.right:parent.right
                        Tag{text:root.clockFull;font.family: "JetBrains Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e";width:200;horizontalAlignment:Text.AlignRight}
                        Tag{text:root.dateStr;font.family: "JetBrains Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e";width:200;horizontalAlignment:Text.AlignRight}
                        Tag{text:root.batText;visible:root.hasBattery;font.family: "JetBrains Mono";font.pixelSize:9;font.letterSpacing:2
                            color: root.batLow ? "#6e2a2a" : "#463f2e";width:200;horizontalAlignment:Text.AlignRight}
                        Tag{text:root.newNotifs + (root.newNotifs === 1 ? " NEW NOTIFICATION" : " NEW NOTIFICATIONS");visible:root.newNotifs > 0
                            font.family: "JetBrains Mono";font.pixelSize:9;font.letterSpacing:2;color:"#6e2a2a";width:200;horizontalAlignment:Text.AlignRight}
                    }
                }
                Item {
                    anchors { bottom:parent.bottom; left:parent.left; bottomMargin:28; leftMargin:30 }
                    z:5; opacity:parent.uiOp
                    Column { spacing:2; anchors.bottom:parent.bottom
                        Tag{text:"KERNEL "+root.kernel;font.family: "JetBrains Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e"}
                        Tag{text:"WM · hyprland";font.family: "JetBrains Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e"}
                    }
                }
                Item {
                    anchors { bottom:parent.bottom; right:parent.right; bottomMargin:28; rightMargin:30 }
                    z:5; opacity:parent.uiOp
                    Column { spacing:2; anchors.bottom:parent.bottom; anchors.right:parent.right
                        Tag{text:root.sysTag;elide:Text.ElideLeft;font.family: "JetBrains Mono";font.pixelSize:9;font.letterSpacing:2;color:"#463f2e";width:220;horizontalAlignment:Text.AlignRight}
                    }
                }

                // Ticker
                Item {
                    anchors{bottom:parent.bottom;bottomMargin:65;left:parent.left;right:parent.right}
                    height:18;z:5;opacity:parent.uiOp;clip:true
                    Rectangle{anchors.fill:parent;color:"#d6cfb5";opacity:0.92}
                    Text {
                        id:tickTxt
                        text:"SYSTEM SCAN · OK ▸ MEMORY INTEGRITY · VERIFIED ▸ SESSION LOCKED · SECURE ▸ NETWORK UPLINK · STABLE ▸ THERMAL · NOMINAL ▸ AUTH DAEMON · LISTENING ▸ "
                        font.family: "JetBrains Mono";font.pixelSize:8;font.letterSpacing:3;color:"#463f2e";y:2
                        NumberAnimation on x { from:(modelData ? modelData.width : 1920); to:-tickTxt.implicitWidth; duration:55000; loops:Animation.Infinite; running:root.frozen }
                    }
                }

                // Panel central — slide depuis le haut (sauf en fast mode)
                Item {
                    id: panelHost
                    width: 380
                    height: panelRect.height
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter:   parent.verticalCenter
                    z: 6
                    opacity: root.fastMode ? 1 : 0

                    SequentialAnimation {
                        id: panelReveal
                        PropertyAction{target:panelHost;property:"anchors.verticalCenterOffset";value:-200}
                        PropertyAction{target:panelHost;property:"opacity";value:0}
                        PropertyAction{target:wipeScale;property:"yScale";value:1}
                        ParallelAnimation {
                            NumberAnimation{target:panelHost;property:"anchors.verticalCenterOffset";to:0;duration:580;easing.type:Easing.OutExpo}
                            NumberAnimation{target:panelHost;property:"opacity";to:1;duration:320}
                        }
                        NumberAnimation{target:wipeScale;property:"yScale";to:0;duration:460;easing.type:Easing.OutExpo}
                        onFinished: {
                            pwInput.forceActiveFocus()
                            focusRetry.restart()
                        }
                    }

                    SequentialAnimation {
                        id: panelHide
                        NumberAnimation{target:wipeScale;property:"yScale";from:0;to:1;duration:210;easing.type:Easing.InQuart}
                        ParallelAnimation{
                            NumberAnimation{target:panelHost;property:"anchors.verticalCenterOffset";to:-200;duration:360;easing.type:Easing.InExpo}
                            NumberAnimation{target:panelHost;property:"opacity";to:0;duration:280}
                        }
                    }

                    SequentialAnimation { id:shakeAnim
                        NumberAnimation{target:panelHost;property:"anchors.horizontalCenterOffset";from:0;to:-10;duration:55}
                        NumberAnimation{target:panelHost;property:"anchors.horizontalCenterOffset";to:10;duration:75}
                        NumberAnimation{target:panelHost;property:"anchors.horizontalCenterOffset";to:-7;duration:65}
                        NumberAnimation{target:panelHost;property:"anchors.horizontalCenterOffset";to:7;duration:65}
                        NumberAnimation{target:panelHost;property:"anchors.horizontalCenterOffset";to:0;duration:55}
                    }

                    Rectangle {
                        id: panelRect
                        width:380; color:"#d6cfb5"
                        height: panelCol.implicitHeight + 72
                        border.color:"#463f2e"; border.width:1

                        Repeater { model:20; Rectangle{x:index*20;y:0;width:1;height:panelRect.height;color:Qt.rgba(70/255,63/255,46/255,0.06)} }
                        Repeater { model:Math.ceil(panelRect.height/20); Rectangle{x:0;y:index*20;width:panelRect.width;height:1;color:Qt.rgba(70/255,63/255,46/255,0.06)} }

                        Rectangle {
                            x:0;width:parent.width;height:1;z:20
                            gradient:Gradient{ orientation:Gradient.Horizontal
                                GradientStop{position:0;color:"transparent"}
                                GradientStop{position:0.5;color:"#6e2a2a"}
                                GradientStop{position:1;color:"transparent"} }
                            SequentialAnimation on y {
                                running:root.frozen;loops:Animation.Infinite
                                NumberAnimation{from:0;to:panelRect.height;duration:3500;easing.type:Easing.Linear}
                                PauseAnimation{duration:600}
                            }
                        }

                        Rectangle {
                            id:wipeCurtain;anchors.fill:parent;color:"#c8b89a";z:50
                            transform:Scale{id:wipeScale;xScale:1;yScale:1;origin.x:0;origin.y:0}
                        }

                        Column {
                            id: panelCol
                            width:308
                            anchors{top:parent.top;topMargin:36;horizontalCenter:parent.horizontalCenter}
                            spacing:0

                            Item { width:parent.width;height:90
                                Rectangle{width:76;height:76;border.color:"#463f2e";border.width:1;color:"transparent"
                                    anchors.horizontalCenter:parent.horizontalCenter
                                    // avatar from ~/.face (the standard login-screen picture), framed like a photo mount
                                    Image {
                                        id: avatar
                                        anchors.fill: parent; anchors.margins: 3
                                        source: "file://" + root.home + "/.face"
                                        sourceSize: Qt.size(140, 140)
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true; mipmap: true
                                    }
                                    // fallback: the original NieR emblem when there is no avatar
                                    Rectangle{width:52;height:52;color:"#463f2e";anchors.centerIn:parent
                                        visible: avatar.status !== Image.Ready
                                        transform:Rotation{angle:45;origin.x:26;origin.y:26}}
                                    Text{text:"NR";font.family: "JetBrains Mono";font.pixelSize:7;color:"#7a7358";opacity:0.5;anchors.top:parent.top;anchors.left:parent.left;anchors.margins:3
                                        visible: avatar.status !== Image.Ready}
                                    Text{text:"2B";font.family: "JetBrains Mono";font.pixelSize:7;color:"#7a7358";opacity:0.5;anchors.bottom:parent.bottom;anchors.right:parent.right;anchors.margins:3
                                        visible: avatar.status !== Image.Ready}
                                }
                            }
                            Text{text:root.currentUser+"@"+root.node;width:parent.width;horizontalAlignment:Text.AlignHCenter;elide:Text.ElideRight;font.family: "JetBrains Mono";font.pixelSize:13;font.letterSpacing:2;color:"#463f2e";anchors.horizontalCenter:parent.horizontalCenter}
                            Item{width:1;height:4}
                            Text{text:"ユニット · アクティブ";font.family: "JetBrains Mono";font.pixelSize:8;color:"#7a7358";anchors.horizontalCenter:parent.horizontalCenter}
                            Item{width:1;height:20}
                            Text{text:root.clockStr;font.family: "JetBrains Mono";font.pixelSize:46;font.letterSpacing:2;color:"#463f2e";anchors.horizontalCenter:parent.horizontalCenter}
                            Item{width:1;height:6}
                            Text{text:root.dateStr;font.family: "JetBrains Mono";font.pixelSize:9;font.letterSpacing:3;color:"#7a7358";anchors.horizontalCenter:parent.horizontalCenter}
                            Item{width:1;height:20}
                            Rectangle{width:parent.width;height:1;color:Qt.rgba(70/255,63/255,46/255,0.22)}
                            Item{width:1;height:22}

                            Item { width:parent.width;height:40
                                Rectangle{anchors.fill:parent;color:"transparent"
                                    border.color:inputScope.activeFocus?"#463f2e":Qt.rgba(70/255,63/255,46/255,0.22);border.width:1
                                    Behavior on border.color{ColorAnimation{duration:200}}}
                                Text{ font.family: "JetBrains Mono";anchors.left:parent.left;anchors.leftMargin:10;anchors.verticalCenter:parent.verticalCenter;text:"▸";font.pixelSize:10;color:"#6e2a2a"}
                                FocusScope {
                                    id:inputScope
                                    anchors{fill:parent;leftMargin:26;rightMargin:10}
                                    focus: root.frozen
                                    TextInput {
                                        id:pwInput;anchors.fill:parent
                                        verticalAlignment:TextInput.AlignVCenter
                                        font.family: "JetBrains Mono";font.pixelSize:12;font.letterSpacing:2
                                        color:"#463f2e";echoMode:TextInput.Password;passwordCharacter:"·"
                                        focus:true;readOnly:false
                                        text:root.lockInput
                                        onTextEdited: { root.lockInput=text }
                                        Keys.onReturnPressed: { root.doAuth() }
                                        Keys.onEscapePressed: { root.lockInput="" }
                                        Text{visible:parent.text==="";anchors.verticalCenter:parent.verticalCenter
                                            text:"password...";font.family: "JetBrains Mono";font.pixelSize:11;font.italic:true;color:"#7a7358";opacity:0.5}
                                    }
                                }
                            }
                            Item{width:1;height:8}

                            Row{anchors.horizontalCenter:parent.horizontalCenter;spacing:6
                                Repeater{model:6;Rectangle{width:6;height:6;color:"transparent";border.color:"#7a7358";border.width:1
                                    Rectangle{visible:index<root.lockInput.length;anchors.fill:parent;color:"#463f2e"}}}}
                            Item{width:1;height:6}

                            Text{text:"AUTHENTICATION FAILED";font.family: "JetBrains Mono";font.pixelSize:8;font.letterSpacing:2;color:"#6e2a2a"
                                anchors.horizontalCenter:parent.horizontalCenter
                                opacity:root.lockError?1:0;height:14;Behavior on opacity{NumberAnimation{duration:200}}}
                            Item{width:1;height:10}

                            Item{width:parent.width;height:42
                                Rectangle{anchors.fill:parent;color:"transparent";border.color:"#463f2e";border.width:1}
                                Rectangle{id:unlockFill;anchors.left:parent.left;anchors.top:parent.top;anchors.bottom:parent.bottom;color:"#463f2e";width:0
                                    Behavior on width{NumberAnimation{duration:280;easing.type:Easing.InOutQuart}}}
                                Text{anchors.centerIn:parent;text:"Login";font.family: "JetBrains Mono";font.pixelSize:10;font.letterSpacing:3
                                    color:unlockMA.containsMouse?"#d6cfb5":"#463f2e";Behavior on color{ColorAnimation{duration:200}}}
                                MouseArea{id:unlockMA;anchors.fill:parent;hoverEnabled:true
                                    onEntered:unlockFill.width=parent.width;onExited:unlockFill.width=0
                                    onClicked:root.doAuth()}
                            }
                        }
                    }
                }

                // ── Now playing (MPRIS) — under the login panel, same style ──
                Rectangle {
                    id: musicCard
                    readonly property var p: root.mprisPlayer
                    visible: root.musicLatched && p !== null && p.trackTitle !== ""
                    // some players (e.g. browsers) don't report playback position
                    readonly property bool hasPos: p !== null && p.positionSupported && p.length > 0
                    anchors.top: panelHost.bottom
                    anchors.topMargin: 18
                    anchors.horizontalCenter: panelHost.horizontalCenter
                    anchors.horizontalCenterOffset: panelHost.anchors.horizontalCenterOffset
                    width: 380; height: 124
                    z: 6
                    opacity: parent.uiOp * panelHost.opacity
                    color: "#d6cfb5"
                    border.color: "#463f2e"; border.width: 1
                    clip: true

                    Repeater { model: 20; Rectangle { x: index*20; width: 1; height: musicCard.height; color: Qt.rgba(70/255,63/255,46/255,0.06) } }
                    Repeater { model: 7;  Rectangle { y: index*20; width: musicCard.width; height: 1; color: Qt.rgba(70/255,63/255,46/255,0.06) } }

                    // header
                    Row {
                        x: 16; y: 10; spacing: 6
                        Rectangle { width: 5; height: 5; radius: 3; color: "#6e2a2a"; anchors.verticalCenter: parent.verticalCenter
                            opacity: musicCard.p && musicCard.p.isPlaying ? 1 : 0.35 }
                        Text { text: "NOW PLAYING · " + (musicCard.p ? String(musicCard.p.identity).toUpperCase() : "")
                               font.family: "JetBrains Mono"; font.pixelSize: 8; font.letterSpacing: 2; color: "#7a7358" }
                    }

                    // cover
                    Rectangle {
                        id: cover
                        x: 16; y: 30; width: 78; height: 78
                        color: "#c8b89a"; border.color: "#463f2e"; border.width: 1
                        Image {
                            id: art
                            anchors.fill: parent; anchors.margins: 1
                            source: root.coverUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            onStatusChanged: if (status === Image.Error) root.failedArt = String(source)
                        }
                        Text { anchors.centerIn: parent; visible: art.status !== Image.Ready
                               text: "♪"; font.pixelSize: 26; color: "#463f2e" }
                    }

                    // text + progress
                    Column {
                        x: cover.x + cover.width + 14; y: 30
                        width: musicCard.width - x - 16
                        spacing: 3
                        Text { width: parent.width; elide: Text.ElideRight
                               text: musicCard.p ? String(musicCard.p.trackTitle).replace(/^\(\d+\)\s*/, "").replace(/\s+-\s+YouTube( Music)?$/, "") : ""
                               font.family: "JetBrains Mono"; font.pixelSize: 12; font.weight: Font.Medium; color: "#463f2e" }
                        Text { width: parent.width; elide: Text.ElideRight
                               text: musicCard.p ? (musicCard.p.trackArtist || musicCard.p.trackAlbum || "") : ""
                               font.family: "JetBrains Mono"; font.pixelSize: 10; color: "#7a7358" }
                        Item { width: 1; height: 6 }
                        Rectangle {
                            width: parent.width; height: 3
                            color: Qt.rgba(70/255,63/255,46/255,0.18)
                            visible: musicCard.hasPos
                            Rectangle {
                                height: parent.height; color: "#463f2e"
                                width: (musicCard.p && musicCard.p.length > 0)
                                       ? parent.width * Math.min(1, musicCard.p.position / musicCard.p.length) : 0
                            }
                        }
                        Item {
                            width: parent.width; height: 26
                            Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                   visible: musicCard.hasPos
                                   text: musicCard.p ? root.fmtTime(musicCard.p.position) + " / " + root.fmtTime(musicCard.p.length) : ""
                                   font.family: "JetBrains Mono"; font.pixelSize: 9; color: "#7a7358" }
                            // controls
                            Row {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Repeater {
                                    model: [
                                        { glyph: "◀◀", act: "prev" },
                                        { glyph: "", act: "toggle" },
                                        { glyph: "▶▶", act: "next" }
                                    ]
                                    Rectangle {
                                        required property var modelData
                                        width: 34; height: 22
                                        color: btnMouse.containsMouse ? "#463f2e" : "transparent"
                                        border.color: "#463f2e"; border.width: 1
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.act === "toggle"
                                                  ? (musicCard.p && musicCard.p.isPlaying ? "❚❚" : "▶") : modelData.glyph
                                            font.pixelSize: 9; font.letterSpacing: -1
                                            color: btnMouse.containsMouse ? "#d6cfb5" : "#463f2e"
                                        }
                                        MouseArea {
                                            id: btnMouse
                                            anchors.fill: parent; hoverEnabled: true
                                            onClicked: {
                                                var pl = musicCard.p; if (!pl) return
                                                if (modelData.act === "prev" && pl.canGoPrevious) pl.previous()
                                                else if (modelData.act === "next" && pl.canGoNext) pl.next()
                                                else if (modelData.act === "toggle" && pl.canTogglePlaying) pl.togglePlaying()
                                                pwInput.forceActiveFocus()   // keep typing the password
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Timer{id:focusRetry;interval:50;repeat:true;property int cnt:0
                    onTriggered:{pwInput.forceActiveFocus();if(++cnt>=8){running=false;cnt=0}}}


                Timer {
                    id: exitTimer; interval: 50; repeat: false
                    onTriggered: Qt.quit()
                }
            }

            Connections {
                target: root
                function onFrozenChanged() {
                    if (root.fastMode && root.frozen) {
                        panelOpenTimer.restart()
                    }
                }
                function onHidingChanged() {
                    if (root.hiding) {
                        reveal.stop()
                        panelHide.start()
                    }
                }
                function onRevealingChanged() {
                    if (root.revealing) {
                        root.frozen = true
                        reveal.position = 0
                        reveal.play()
                        panelOpenTimer.restart()
                    }
                }
                function onLockErrorChanged() {
                    if (root.lockError) shakeAnim.restart()
                }
            }

            Timer {
                id: panelOpenTimer
                interval: 100
                repeat: false
                onTriggered: {
                    if (root.fastMode) {
                        wipeScale.yScale = 0
                        pwInput.forceActiveFocus()
                        focusRetry.restart()
                    } else {
                        panelReveal.start()
                    }
                }
            }

            Component.onCompleted: {
                if (!root.fastMode) {
                    reveal.position = 0
                    reveal.play()
                }
                // Session-lock surfaces are created after the lock has started, so they miss the
                // frozen/revealing change that opens the panel: open it from the current state.
                if (root.frozen || root.revealing) panelOpenTimer.restart()
            }
        }
    }

    // ── Unlock wipe: a transparent overlay that plays the wave over the (now unlocked) desktop ──
    Variants {
        model: root.hiding ? Quickshell.screens : []
        PanelWindow {
            id: wipeWin
            required property var modelData
            screen: modelData
            anchors { top: true; left: true; right: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "unit3-unlock-wipe"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            readonly property bool isPrimary: modelData.name === Quickshell.screens[0].name
            readonly property bool hideStarted: hide.position > 0

            // the lock's background, until the wave's first frame is ready
            Image {
                anchors.fill: parent
                source: "file://" + root.xdgConfigHome + "/quickshell/videos/wave_last_frame.png"
                fillMode: Image.PreserveAspectCrop
                visible: !wipeWin.hideStarted
            }
            MediaPlayer {
                id: hide
                source: "file://" + root.xdgConfigHome + "/quickshell/videos/wave_hide.mp4"
                videoOutput: voHide
                audioOutput: null
                Component.onCompleted: play()
            }
            VideoOutput {
                id: voHide
                anchors.fill: parent
                // key out the black of the wave so it uncovers the desktop
                layer.enabled: true
                layer.effect: ShaderEffect {
                    property variant source
                    fragmentShader: Qt.resolvedUrl("lumakey.frag.qsb")
                }
            }
            Timer { interval: 800; running: true; onTriggered: wipeFade.start() }
            NumberAnimation {
                id: wipeFade
                target: voHide; property: "opacity"; to: 0.0
                duration: 400; easing.type: Easing.InQuad
                onFinished: if (wipeWin.isPrimary) Qt.quit()
            }
        }
    }
    // safety net: never linger after unlocking
    Timer { running: root.hiding; interval: 4000; onTriggered: Qt.quit() }

    // Horloge
    property string clockStr:  "--:--"
    property string dateStr:   "---- / -- / --"
    property string clockFull: "--:--:--"
    Timer {
        interval:1000;running:true;repeat:true;triggeredOnStart:true
        onTriggered:{
            var d=new Date(),p=function(x){return String(x).padStart(2,"0")}
            root.clockStr  = p(d.getHours())+":"+p(d.getMinutes())
            root.clockFull = p(d.getHours())+":"+p(d.getMinutes())+":"+p(d.getSeconds())
            root.dateStr   = d.getFullYear()+" / "+p(d.getMonth()+1)+" / "+p(d.getDate())
        }
    }
}