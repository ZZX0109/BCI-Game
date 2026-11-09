import QtQuick
import "../shared-ui" as SharedUI
Rectangle {
    id: button
    SharedUI.GameTheme { id: uiTheme }
    property string text: ""
    property string detail: ""
    property color accent: "#8EE6BD"
    property color detailColor: "#B8C6CE"
    property bool swatch: false
    property bool highlighted: false
    property bool available: true
    signal activated()
    width: 140; height: 48; radius: 4
    color: mouse.pressed ? "#24251F" : highlighted ? "#151713" : mouse.containsMouse ? "#171817" : "transparent"
    border.width: highlighted ? 1 : 0
    border.color: accent
    opacity: available ? 1 : 0.5
    Accessible.role: Accessible.Button
    Accessible.name: text + (detail ? ", " + detail : "")
    Accessible.onPressAction: if (available) button.activated()
    Rectangle { visible: button.swatch; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 5; height: 18; radius: 2; color: button.accent }
    Column {
        anchors.centerIn: parent
        spacing: 2
        Text { font.family: uiTheme.fontFamily; anchors.horizontalCenter: parent.horizontalCenter; text: button.text; color: button.highlighted ? button.accent : "#F4F1E9"; font.pixelSize: 15; font.bold: true }
        Text { font.family: uiTheme.fontFamily; anchors.horizontalCenter: parent.horizontalCenter; visible: button.detail !== ""; text: button.detail; color: button.detailColor; font.pixelSize: 14 }
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; enabled: button.available; onClicked: button.activated() }
}
