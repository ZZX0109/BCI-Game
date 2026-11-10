import QtQuick
Item {
    width: 1000; height: 700
    property alias loadedGame: loader.item
    property alias mockHost: host
    QtObject {
        id: host
        property string inputSource: "local"
        property real elapsedSeconds: 0
        property real width: 1000
        property real height: 700
        signal started()
        signal step(real seconds)
        signal pointer(real x, real y)
        signal action(string name, bool pressed)
        signal paused()
        signal resumed()
        signal stopping()
        function record(name, value) { bridge.record(name, JSON.stringify(value)) }
        function finish(value) { bridge.finish(JSON.stringify(value)) }
    }
    QtObject {
        id: context
        property var config: ({read: function(defaults) {return defaults}})
    }
    Loader { id: loader; anchors.fill: parent }
    function loadGame(url) { loader.source=""; loader.setSource(url, {game: host, taskContext: context}) }
}
