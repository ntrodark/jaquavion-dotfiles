import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property string title:    ""
    property string artist:   ""
    property string album:    ""
    property string artUrl:   ""
    property bool   playing:  false
    property real   position: 0
    property real   duration: 0
    property int    volume:   65

    property var _proc: Process {
        id: metaProc
        command: ["playerctl", "--player=%any", "metadata", "--format",
                  "{{title}}|{{artist}}|{{album}}|{{mpris:artUrl}}|{{status}}|{{position}}|{{mpris:length}}"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim().split("|")
                if (p.length < 7) return
                root.title    = p[0]
                root.artist   = p[1]
                root.album    = p[2]
                root.artUrl   = p[3].replace("https://", "http://")
                root.playing  = p[4] === "Playing"
                root.position = parseInt(p[5]) / 1000000
                root.duration = parseInt(p[6]) / 1000000
            }
        }
    }

    property var _timer: Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: metaProc.running = true
    }

    function playPause() { _run(["playerctl", "--player=%any", "play-pause"]) }
    function next()      { _run(["playerctl", "--player=%any", "next"]) }
    function prev()      { _run(["playerctl", "--player=%any", "previous"]) }
    function seek(s)     { _run(["playerctl", "--player=%any", "position", String(s)]) }
    function setVol(v)   {
        root.volume = v
        _run(["playerctl", "--player=%any", "volume", String(v / 100)])
    }
    function _run(cmd) {
        var p = Qt.createQmlObject('import Quickshell.Io; Process {}', root)
        p.command = cmd
        p.running = true
    }
}
