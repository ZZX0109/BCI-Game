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
        if (toastType === "success") return theme.primary
        if (toastType === "warning") return theme.warning
        if (toastType === "danger") return theme.danger
        return theme.panelBorder
    }
    opacity: 0

    Text {
        id: toastText
        anchors.centerIn: parent
        text: root.text
        color: theme.background
        font.pixelSize: theme.bodyPx
        font.family: theme.fontFamily
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
