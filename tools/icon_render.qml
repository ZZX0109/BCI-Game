import QtQuick
import QtQuick.Controls
ApplicationWindow {
    width: 0; height: 0; visible: false
    Component.onCompleted: {
        for (var i = 0; i < Qt.arguments.length; i++) {}
    }
}
