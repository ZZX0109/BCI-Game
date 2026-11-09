import QtQuick

Rectangle {
    id: root
    required property var theme
    property string text: ""
    property string toastType: "info"
    z: 1000
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.min(88, parent.height * 0.15)
    width: Math.min(Math.max(180, toastText.implicitWidth + 40), Math.max(120, parent.width - 32))
    height: toastText.contentHeight + 24
    radius: 10
    border.width: 1
    border.color: toastType === "danger" ? theme.danger : (toastType === "warning" ? theme.warning : theme.primary)
    color: theme.panel
    opacity: 0
    visible: opacity > 0
    Accessible.role: Accessible.StaticText
    Accessible.name: text
    Text {
        id: toastText
        anchors.centerIn: parent
        width: parent.width - 32
        text: root.text
        color: root.theme.primaryText
        font.pixelSize: root.theme.bodyPx
        font.family: root.theme.fontFamily
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
    }
    function show(msg, type) { text = msg; toastType = type || "info"; toastAnim.restart() }
    SequentialAnimation {
        id: toastAnim
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: 90 }
        PauseAnimation { duration: 2200 }
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 180 }
    }
}
