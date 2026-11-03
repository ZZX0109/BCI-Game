import QtQuick

// 统一外框：顶栏、底栏、主场景容器。游戏世界内容通过 contentItem 注入。
Rectangle {
    id: root
    color: theme.background

    required property var theme
    property string title: ""
    property string subtitle: ""
    property string mode: ""
    property string inputSource: "LOCAL"
    property alias contentItem: contentItem
    property alias overlayItem: overlayItem
    property alias bottomBar: bottomBar

    // 顶部栏
    Rectangle {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: theme.frameTopHeight
        color: theme.panel

        Text {
            id: titleText
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            color: theme.primaryText
            font.pixelSize: theme.titlePx
            font.bold: true
        }

        Text {
            id: subtitleText
            anchors.left: titleText.left
            anchors.top: titleText.bottom
            anchors.topMargin: 2
            visible: root.subtitle !== ""
            text: root.subtitle
            color: theme.secondaryText
            font.pixelSize: theme.captionPx
        }

        Text {
            id: inputBadge
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            text: "[" + root.inputSource.toUpperCase() + "]"
            color: theme.primary
            font.pixelSize: theme.captionPx
            font.bold: true
        }

        Text {
            anchors.right: inputBadge.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: root.mode
            color: theme.secondaryText
            font.pixelSize: theme.bodyPx
        }
    }

    // 主场景容器
    Item {
        id: sceneViewport
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bottomBar.top
        anchors.margins: 12
        clip: true

        Item {
            id: contentItem
            anchors.fill: parent
        }
    }

    // 底栏
    Rectangle {
        id: bottomBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: theme.frameBottomHeight
        color: theme.panel
    }

    // 浮层（暂停/对话框等）
    Item {
        id: overlayItem
        anchors.fill: parent
        z: 100
    }
}
