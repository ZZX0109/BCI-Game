import QtQuick

// 短时反馈提示，不遮挡核心操作，自动消失
Rectangle {
    id: root

    required property var theme
    property string text: ""
    property string toastType: "info" // info | success | warning | danger

    anchors.horizontalCenter: parent.horizontalCenter
    y: -height - 20
    width: toastText.width + 32
    height: toastText.height + 20
    radius: theme.buttonRadius
    color: {
        if (toastType === "success") return Qt.rgba(0.18, 0.55, 0.55, 0.95)
        if (toastType === "warning") return Qt.rgba(0.72, 0.51, 0.17, 0.95)
        if (toastType === "danger") return Qt.rgba(0.77, 0.33, 0.33, 0.95)
        return Qt.rgba(0.21, 0.54, 0.61, 0.95)
    }
    opacity: 0

    Text {
        id: toastText
        anchors.centerIn: parent
        text: root.text
        color: "#FFFFFF"
        font.pixelSize: theme.bodyPx
        font.bold: true
    }

    function show(msg, type) {
        text = msg
        toastType = type || "info"
        toastAnim.restart()
    }

    SequentialAnimation {
        id: toastAnim
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: 180 }
        NumberAnimation { target: root; property: "y"; to: 24; duration: 200; easing.type: Easing.OutBack }
        PauseAnimation { duration: 1400 }
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 200 }
        NumberAnimation { target: root; property: "y"; to: -root.height - 20; duration: 200 }
    }
}
