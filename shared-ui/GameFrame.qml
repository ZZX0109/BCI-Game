import QtQuick

// 统一外框：对齐宿主样例 pong/balance 的视觉语言——
// 全出血暗色场景 + 米白粗边框 + 悬浮文字 HUD，不使用面板条。
Rectangle {
    id: root
    color: theme.background
    border.width: 4
    border.color: theme.primaryText

    required property var theme
    property string title: ""
    property string subtitle: ""
    property string mode: ""
    property string inputSource: "LOCAL"
    property alias contentItem: contentItem
    property alias overlayItem: overlayItem
    // 兼容旧接口：游戏仍可把提示行 parent 到 bottomBar；
    // 现为透明悬浮层，仅承载文字/按钮，不再画面板。
    property alias bottomBar: bottomBar

    // 主场景：全出血
    Item {
        id: contentItem
        anchors.fill: parent
    }

    // 顶部悬浮 HUD（透明，仅文字，pong 式大标题居中）
    Item {
        id: topHud
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 72
        z: 50

        Text {
            id: titleText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 10
            text: root.title
            color: "#dddddd"
            font.pixelSize: 28
            font.family: theme.fontFamily
            font.bold: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: titleText.bottom
            anchors.topMargin: 2
            visible: root.subtitle !== ""
            text: root.subtitle
            color: theme.secondaryText
            font.pixelSize: theme.captionPx
            font.family: theme.fontFamily
        }

        Text {
            id: inputBadge
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.top: parent.top
            anchors.topMargin: 14
            text: "[" + root.inputSource.toUpperCase() + "]"
            color: theme.primary
            font.pixelSize: theme.captionPx
            font.family: theme.fontFamily
            font.bold: true
        }

        Text {
            anchors.right: inputBadge.left
            anchors.rightMargin: 16
            anchors.top: parent.top
            anchors.topMargin: 14
            text: root.mode
            color: theme.secondaryText
            font.pixelSize: theme.bodyPx
            font.family: theme.fontFamily
        }
    }

    // 底部悬浮层（透明）：提示文字/鼠标按钮仍可挂在这里
    Item {
        id: bottomBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 64
        z: 50
    }

    // 浮层（暂停/对话框等）
    Item {
        id: overlayItem
        anchors.fill: parent
        z: 100
    }
}
