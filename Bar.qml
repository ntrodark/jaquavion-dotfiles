import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: sidebar

    anchors { left: true; top: true; bottom: true }
    implicitWidth: 220
    exclusiveZone: 220
    color: "#FBF1C7"

    readonly property color bg:   "#FBF1C7"
    readonly property color fg:   "#1C1C1C"
    readonly property color mid:  "#8C8272"
    readonly property color line: "#C8BB96"
    readonly property color red:  "#CC241D"

    property string uptimeText:   "–"
    property string weatherText:  "–"
    property string diskText:     "–"
    property string ramText:      "–"
    property string wifiSSID:     "–"
    property int    wifiStrength: 0
    property real   volLevel:     0.65
    property bool   volMuted:     false
    property var    todos:        []
    property bool   powerConfirm: false
    property string powerAction:  ""
    property int    pomodoroSecs: 25 * 60
    property bool   pomodoroRunning: false
    property bool   pomodoroBreak:   false

    property var  battery:     UPower.devices.find(d => d.type === UPowerDeviceType.Battery) ?? null
    property real batPct:      battery ? Math.round(battery.percentage * 100) : -1
    property bool batCharging: battery ? battery.state === UPowerDeviceState.Charging : false

    Process {
        id: uptimeProc
        command: ["sh", "-c", "uptime -p | sed 's/up //'"]
        running: true
        stdout: StdioCollector { onStreamFinished: sidebar.uptimeText = text.trim() }
    }

    Process {
        id: weatherProc
        command: ["sh", "-c", "curl -sf 'wttr.in/?format=%t+%C' 2>/dev/null || echo '–'"]
        running: true
        stdout: StdioCollector { onStreamFinished: sidebar.weatherText = text.trim() }
    }

    Process {
        id: diskProc
        command: ["sh", "-c", "df -h / | awk 'NR==2{print $3\"/\"$2\" (\"$5\")\"}'"]
        running: true
        stdout: StdioCollector { onStreamFinished: sidebar.diskText = text.trim() }
    }

    Process {
        id: ramProc
        command: ["sh", "-c", "free -h | awk '/^Mem/{print $3\"/\"$2}'"]
        running: true
        stdout: StdioCollector { onStreamFinished: sidebar.ramText = text.trim() }
    }

    Process {
        id: wifiProc
        command: ["sh", "-c", "iwgetid -r 2>/dev/null || echo '–'"]
        running: true
        stdout: StdioCollector { onStreamFinished: sidebar.wifiSSID = text.trim() }
    }

    Process {
        id: wifiStrengthProc
        command: ["sh", "-c",
            "awk 'NR==3{gsub(/\\./, \"\"); print int($3 * 100 / 70)}' /proc/net/wireless 2>/dev/null || echo 0"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: sidebar.wifiStrength = Math.min(100, parseInt(text.trim()) || 0)
        }
    }

    Process {
        id: volProc
        command: ["sh", "-c",
            "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || amixer sget Master | grep -o '[0-9]*%' | head -1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.trim()
                if (t.includes("Volume:")) {
                    var parts = t.split(" ")
                    sidebar.volLevel = parseFloat(parts[1]) || 0.65
                    sidebar.volMuted = t.includes("[MUTED]")
                } else {
                    sidebar.volLevel = (parseInt(t) || 65) / 100
                }
            }
        }
    }

    Timer {
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            uptimeProc.running       = true
            weatherProc.running      = true
            diskProc.running         = true
            ramProc.running          = true
            wifiProc.running         = true
            wifiStrengthProc.running = true
            volProc.running          = true
        }
    }

    Timer {
        id: pomTimer
        interval: 1000; repeat: true
        running: sidebar.pomodoroRunning
        onTriggered: {
            if (sidebar.pomodoroSecs > 0) {
                sidebar.pomodoroSecs--
            } else {
                sidebar.pomodoroRunning = false
                sidebar.pomodoroBreak   = !sidebar.pomodoroBreak
                sidebar.pomodoroSecs    = sidebar.pomodoroBreak ? 5 * 60 : 25 * 60
                var p = Qt.createQmlObject('import Quickshell.Io; Process {}', sidebar)
                p.command = ["notify-send", "-t", "4000",
                    sidebar.pomodoroBreak ? "Break time!" : "Focus time!",
                    sidebar.pomodoroBreak ? "Take a 5 min break" : "25 min focus session"]
                p.running = true
            }
        }
    }

    function pomFmt() {
        var m = Math.floor(pomodoroSecs / 60)
        var s = pomodoroSecs % 60
        return m + ":" + (s < 10 ? "0"+s : s)
    }

    function setVol(v) {
        volLevel = Math.max(0, Math.min(1, v))
        var p = Qt.createQmlObject('import Quickshell.Io; Process {}', sidebar)
        p.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", String(Math.round(volLevel * 100)) + "%"]
        p.running = true
    }

    function toggleMute() {
        volMuted = !volMuted
        var p = Qt.createQmlObject('import Quickshell.Io; Process {}', sidebar)
        p.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        p.running = true
    }

    function run(cmd) {
        var p = Qt.createQmlObject('import Quickshell.Io; Process {}', sidebar)
        p.command = cmd
        p.running = true
    }

    function addTodo() {
        if (todoInput.text.trim() === "") return
        var t = todos.slice()
        t.push(todoInput.text.trim())
        todos = t
        todoInput.text = ""
        saveTodos()
    }

    function saveTodos() {
        var p = Qt.createQmlObject('import Quickshell.Io; Process {}', sidebar)
        p.command = ["sh", "-c",
            "printf '%s' " + "'" + JSON.stringify(todos) + "'" +
            " > ~/.config/quickshell/todos.json"]
        p.running = true
    }

    function loadTodos() {
        var lp = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', sidebar)
        lp.command = ["sh", "-c", "cat ~/.config/quickshell/todos.json 2>/dev/null || echo '[]'"]
        lp.stdout.onStreamFinished.connect(function() {
            try { sidebar.todos = JSON.parse(lp.stdout.text) } catch(e) {}
        })
        lp.running = true
    }

    Component.onCompleted: loadTodos()

    // ── Scrollable content ──
    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainCol.implicitHeight
        clip: true

        Column {
            id: mainCol
            width: sidebar.implicitWidth
            spacing: 0
            topPadding: 44

            // ── POWER ──
            Item {
                width: parent.width
                height: pwCol.implicitHeight + 24

                Column {
                    id: pwCol
                    anchors { left: parent.left; right: parent.right; margins: 12 }
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        text: "POWER"
                        font.family: "Monospace"; font.pixelSize: 8
                        font.letterSpacing: 2; color: sidebar.mid
                    }

                    Rectangle {
                        width: parent.width; height: 36; radius: 6
                        color: sidebar.red
                        visible: sidebar.powerConfirm

                        Row {
                            anchors.centerIn: parent
                            spacing: 12

                            Text {
                                text: sidebar.powerAction + "?"
                                font.family: "Monospace"; font.pixelSize: 11
                                color: sidebar.bg
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Rectangle {
                                width: 40; height: 24; radius: 4; color: sidebar.bg
                                Text { anchors.centerIn: parent; text: "yes"; font.family: "Monospace"; font.pixelSize: 10; color: sidebar.red }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        sidebar.powerConfirm = false
                                        if (sidebar.powerAction === "shutdown") sidebar.run(["systemctl", "poweroff"])
                                        else if (sidebar.powerAction === "reboot")  sidebar.run(["systemctl", "reboot"])
                                        else if (sidebar.powerAction === "suspend") sidebar.run(["systemctl", "suspend"])
                                        else if (sidebar.powerAction === "lock")    sidebar.run(["hyprlock"])
                                    }
                                }
                            }

                            Rectangle {
                                width: 40; height: 24; radius: 4
                                color: "transparent"; border.color: sidebar.bg; border.width: 1
                                Text { anchors.centerIn: parent; text: "no"; font.family: "Monospace"; font.pixelSize: 10; color: sidebar.bg }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: sidebar.powerConfirm = false
                                }
                            }
                        }
                    }

                    Grid {
                        columns: 4; spacing: 6; width: parent.width
                        visible: !sidebar.powerConfirm

                        Repeater {
                            model: [
                                { label: "⏻", action: "shutdown", tip: "off"     },
                                { label: "↺", action: "reboot",   tip: "reboot"  },
                                { label: "⏾", action: "suspend",  tip: "sleep"   },
                                { label: "⏽", action: "lock",     tip: "lock"    }
                            ]

                            Rectangle {
                                width: (pwCol.width - 18) / 4; height: width; radius: 6
                                color: "transparent"; border.color: sidebar.line; border.width: 1

                                Column {
                                    anchors.centerIn: parent; spacing: 2
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; font.pixelSize: 16; color: sidebar.fg }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.tip; font.family: "Monospace"; font.pixelSize: 7; color: sidebar.mid }
                                }

                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { sidebar.powerAction = modelData.action; sidebar.powerConfirm = true }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: sidebar.line }

            // ── VOLUME ──
            Item {
                width: parent.width; height: volCol.implicitHeight + 24

                Column {
                    id: volCol
                    anchors { left: parent.left; right: parent.right; margins: 12 }
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text { text: "VOLUME"; font.family: "Monospace"; font.pixelSize: 8; font.letterSpacing: 2; color: sidebar.mid }

                    Row {
                        width: parent.width; spacing: 8

                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: sidebar.volMuted ? sidebar.fg : "transparent"
                            border.color: sidebar.line; border.width: 1
                            anchors.verticalCenter: parent.verticalCenter

                            Text { anchors.centerIn: parent; text: sidebar.volMuted ? "✕" : "♪"; font.pixelSize: 12; color: sidebar.volMuted ? sidebar.bg : sidebar.fg }

                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sidebar.toggleMute() }
                        }

                        Item {
                            width: parent.width - 44; height: 28
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                width: parent.width; height: 3; color: sidebar.line; anchors.verticalCenter: parent.verticalCenter; radius: 2
                                Rectangle {
                                    width: parent.width * (sidebar.volMuted ? 0 : sidebar.volLevel)
                                    height: 3; color: sidebar.fg; radius: 2
                                }
                            }

                            Rectangle {
                                width: 10; height: 10; radius: 5
                                color: sidebar.bg; border.color: sidebar.fg; border.width: 1.5
                                anchors.verticalCenter: parent.verticalCenter
                                x: (parent.width * sidebar.volLevel) - 5
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: mouse => sidebar.setVol(mouse.x / width)
                                onPositionChanged: mouse => { if (pressed) sidebar.setVol(mouse.x / width) }
                            }
                        }
                    }

                    Text { text: sidebar.volMuted ? "muted" : Math.round(sidebar.volLevel * 100) + "%"; font.family: "Monospace"; font.pixelSize: 10; color: sidebar.mid }
                }
            }

            Rectangle { width: parent.width; height: 1; color: sidebar.line }

            // ── WIFI ──
            Item {
                width: parent.width; height: wifiCol.implicitHeight + 24

                Column {
                    id: wifiCol
                    anchors { left: parent.left; right: parent.right; margins: 12 }
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text { text: "NETWORK"; font.family: "Monospace"; font.pixelSize: 8; font.letterSpacing: 2; color: sidebar.mid }

                    Row {
                        width: parent.width; spacing: 8

                        Column {
                            spacing: 2; anchors.verticalCenter: parent.verticalCenter
                            Text { text: sidebar.wifiSSID; font.family: "Monospace"; font.pixelSize: 11; color: sidebar.fg }
                            Text { text: sidebar.wifiStrength + "% signal"; font.family: "Monospace"; font.pixelSize: 9; color: sidebar.mid }
                        }

                        Item { width: parent.width - 130 }

                        Row {
                            spacing: 2; anchors.verticalCenter: parent.verticalCenter
                            Repeater {
                                model: 4
                                Rectangle {
                                    width: 5; height: 6 + index * 4
                                    anchors.bottom: parent.bottom; radius: 1
                                    color: (index + 1) * 25 <= sidebar.wifiStrength ? sidebar.fg : sidebar.line
                                }
                            }
                        }
                    }

                    Row {
                        spacing: 6

                        Rectangle {
                            width: 70; height: 24; radius: 4; color: sidebar.fg
                            Text { anchors.centerIn: parent; text: "toggle"; font.family: "Monospace"; font.pixelSize: 9; color: sidebar.bg }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sidebar.run(["nmcli", "radio", "wifi", "toggle"]) }
                        }

                        Rectangle {
                            width: 70; height: 24; radius: 4; color: "transparent"; border.color: sidebar.line; border.width: 1
                            Text { anchors.centerIn: parent; text: "scan"; font.family: "Monospace"; font.pixelSize: 9; color: sidebar.fg }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { sidebar.run(["nmcli", "device", "wifi", "rescan"]); wifiProc.running = true; wifiStrengthProc.running = true }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: sidebar.line }

            // ── BATTERY ──
            Item {
                width: parent.width; height: batCol.implicitHeight + 24
                visible: sidebar.batPct >= 0

                Column {
                    id: batCol
                    anchors { left: parent.left; right: parent.right; margins: 12 }
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text { text: "BATTERY"; font.family: "Monospace"; font.pixelSize: 8; font.letterSpacing: 2; color: sidebar.mid }

                    Row {
                        spacing: 10
                        Text {
                            text: sidebar.batPct + "%"
                            font.family: "Serif"; font.pixelSize: 22; font.weight: Font.Black
                            color: sidebar.batPct < 20 ? sidebar.red : sidebar.fg
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: sidebar.batCharging ? "charging ↑" : "on battery"
                            font.family: "Monospace"; font.pixelSize: 9
                            color: sidebar.batCharging ? "#689D6A" : sidebar.mid
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Item {
                        width: parent.width; height: 8
                        Rectangle {
                            width: parent.width; height: 8; radius: 4; color: sidebar.line
                            Rectangle {
                                width: parent.width * (sidebar.batPct / 100); height: 8; radius: 4
                                color: sidebar.batPct < 20 ? sidebar.red : sidebar.batCharging ? "#689D6A" : sidebar.fg
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: sidebar.line; visible: sidebar.batPct >= 0 }

            // ── SYSTEM ──
            Item {
                width: parent.width; height: sysCol.implicitHeight + 24

                Column {
                    id: sysCol
                    anchors { left: parent.left; right: parent.right; margins: 12 }
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text { text: "SYSTEM"; font.family: "Monospace"; font.pixelSize: 8; font.letterSpacing: 2; color: sidebar.mid }

                    Repeater {
                        model: [
                            { k: "uptime",  v: sidebar.uptimeText  },
                            { k: "disk",    v: sidebar.diskText    },
                            { k: "ram",     v: sidebar.ramText     },
                            { k: "weather", v: sidebar.weatherText }
                        ]
                        Row {
                            spacing: 8
                            Text { text: modelData.k; font.family: "Monospace"; font.pixelSize: 9; color: sidebar.mid; width: 52 }
                            Text { text: modelData.v; font.family: "Monospace"; font.pixelSize: 10; color: sidebar.fg; width: sysCol.width - 60; elide: Text.ElideRight }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: sidebar.line }

            // ── TO-DO ──
            Item {
                width: parent.width; height: todoCol.implicitHeight + 24

                Column {
                    id: todoCol
                    anchors { left: parent.left; right: parent.right; margins: 12 }
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text { text: "TO-DO"; font.family: "Monospace"; font.pixelSize: 8; font.letterSpacing: 2; color: sidebar.mid }

                    Repeater {
                        model: sidebar.todos
                        Row {
                            width: todoCol.width; spacing: 8

                            Rectangle {
                                width: 14; height: 14; radius: 7; color: "transparent"
                                border.color: sidebar.line; border.width: 1
                                anchors.verticalCenter: parent.verticalCenter
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var t = sidebar.todos.slice(); t.splice(index, 1); sidebar.todos = t; sidebar.saveTodos()
                                    }
                                }
                            }

                            Text { text: modelData; font.family: "Monospace"; font.pixelSize: 10; color: sidebar.fg; width: parent.width - 22; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }

                    Row {
                        width: parent.width; spacing: 6

                        Rectangle {
                            width: parent.width - 36; height: 26; color: "transparent"
                            border.color: sidebar.line; border.width: 1; radius: 4
                            TextInput {
                                id: todoInput
                                anchors.fill: parent; anchors.margins: 6
                                font.family: "Monospace"; font.pixelSize: 10; color: sidebar.fg; clip: true
                                onAccepted: sidebar.addTodo()
                            }
                        }

                        Rectangle {
                            width: 26; height: 26; radius: 4; color: sidebar.fg
                            Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; color: sidebar.bg }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sidebar.addTodo() }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: sidebar.line }

            // ── POMODORO ──
            Item {
                width: parent.width; height: pomCol.implicitHeight + 24

                Column {
                    id: pomCol
                    anchors { left: parent.left; right: parent.right; margins: 12 }
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text { text: "POMODORO"; font.family: "Monospace"; font.pixelSize: 8; font.letterSpacing: 2; color: sidebar.mid }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: sidebar.pomFmt()
                        font.family: "Serif"; font.pixelSize: 32; font.weight: Font.Black
                        color: sidebar.pomodoroBreak ? "#689D6A" : sidebar.fg
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: sidebar.pomodoroBreak ? "break" : "focus"
                        font.family: "Monospace"; font.pixelSize: 9; font.letterSpacing: 2; color: sidebar.mid
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: 8

                        Rectangle {
                            width: 60; height: 28; radius: 4; color: sidebar.fg
                            Text { anchors.centerIn: parent; text: sidebar.pomodoroRunning ? "pause" : "start"; font.family: "Monospace"; font.pixelSize: 10; color: sidebar.bg }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sidebar.pomodoroRunning = !sidebar.pomodoroRunning }
                        }

                        Rectangle {
                            width: 60; height: 28; radius: 4; color: "transparent"; border.color: sidebar.line; border.width: 1
                            Text { anchors.centerIn: parent; text: "reset"; font.family: "Monospace"; font.pixelSize: 10; color: sidebar.fg }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { sidebar.pomodoroRunning = false; sidebar.pomodoroBreak = false; sidebar.pomodoroSecs = 25 * 60 }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: sidebar.line }

            // ── LAUNCHER ──
            Item {
                width: parent.width; height: launchCol.implicitHeight + 24

                Column {
                    id: launchCol
                    anchors { left: parent.left; right: parent.right; margins: 12 }
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text { text: "LAUNCH"; font.family: "Monospace"; font.pixelSize: 8; font.letterSpacing: 2; color: sidebar.mid }

                    Grid {
                        columns: 3; spacing: 6; width: parent.width

                        Repeater {
                            model: [
                                { name: "term",    cmd: ["alacritty"] },
                                { name: "files",   cmd: ["nautilus"]  },
                                { name: "editor",  cmd: ["code"]      },
                                { name: "discord", cmd: ["discord"]   },
                                { name: "obs",     cmd: ["obs"]       },
                                { name: "gimp",    cmd: ["gimp"]      }
                            ]

                            Rectangle {
                                width: (launchCol.width - 12) / 3; height: 36; radius: 6
                                color: "transparent"; border.color: sidebar.line; border.width: 1

                                Text { anchors.centerIn: parent; text: modelData.name; font.family: "Monospace"; font.pixelSize: 9; color: sidebar.fg }

                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: sidebar.run(["hyprctl", "dispatch", "exec"].concat(modelData.cmd))
                                }
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: 16 }
        }
    }
}
