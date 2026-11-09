import QtQuick

// 开放场景：所有游戏共享留白与悬浮 HUD，不绘制游戏外框。
Rectangle {
    id: root
    color: theme.background
    border.width: 0

    required property var theme
    property string title: ""
    property string subtitle: ""
    property string mode: ""
    property string inputSource: "LOCAL"
    property bool legacyWindowFillEnabled: true
    readonly property real hudScale: Math.min(1.4, Math.max(1, Math.min(width, height) / 700))
    readonly property real contentInset: Math.max(20, Math.min(40, width * 0.025))
    readonly property real sceneTop: 104
    readonly property real sceneBottom: 88
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

    // HUD 不占据场景坐标；布局变化不会改变指针到场景的映射。
    Item {
        id: topHud
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.sceneTop
        z: 50

        Text {
            id: titleText
            anchors.left: parent.left
            anchors.leftMargin: root.contentInset
            anchors.top: parent.top
            anchors.topMargin: 18
            width: Math.max(1, root.width * 0.58 - root.contentInset)
            elide: Text.ElideRight
            text: root.title
            color: theme.primaryText
            font.pixelSize: Math.min(26 * root.hudScale, root.width * 0.038)
            font.family: theme.fontFamily
            font.weight: Font.DemiBold
        }

        Text {
            anchors.left: titleText.left
            anchors.top: titleText.bottom
            anchors.topMargin: 5
            visible: root.subtitle !== ""
            text: root.subtitle
            width: titleText.width
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
            color: theme.secondaryText
            font.pixelSize: Math.round(theme.captionPx * root.hudScale)
            font.family: theme.fontFamily
        }

        Text {
            id: inputBadge
            anchors.right: parent.right
            anchors.rightMargin: root.contentInset
            anchors.top: titleText.bottom
            anchors.topMargin: 5
            width: Math.max(1, root.width * 0.36 - root.contentInset)
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: /bci|brain/i.test(root.inputSource) ? "脑控" : "鼠标 / 键盘"
            color: theme.secondaryText
            font.pixelSize: Math.round(theme.captionPx * root.hudScale)
            font.family: theme.fontFamily
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: root.contentInset
            anchors.top: parent.top
            anchors.topMargin: 18
            text: root.mode
            width: Math.max(1, root.width * 0.36 - root.contentInset)
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            color: theme.primaryText
            font.pixelSize: Math.round(theme.bodyPx * root.hudScale)
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
    LegacyWindowFill {
        id: windowFill
        objectName: "legacyWindowFill"
        gameRoot: root.parent
        autoFillEnabled: root.legacyWindowFillEnabled
    }
    LayoutProbe {
        objectName: "runtimeLayoutProbe"
        anchors.fill: parent
        theme: root.theme
        gameRoot: root.parent
        adaptationStatus: windowFill.statusText
        z: 5000
    }
}
