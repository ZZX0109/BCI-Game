import QtQuick

// 场景视口：保持 1000×700 设计坐标并等比缩放
Rectangle {
    id: root

    required property var theme
    property alias scene: sceneItem.children
    property real designWidth: 1000
    property real designHeight: 700

    color: theme.background
    border.color: theme.panelBorder
    border.width: 1

    Item {
        id: sceneItem
        width: root.designWidth
        height: root.designHeight
        anchors.centerIn: parent
        scale: Math.min(root.width / root.designWidth, root.height / root.designHeight)
        transformOrigin: Item.Center
    }
}
