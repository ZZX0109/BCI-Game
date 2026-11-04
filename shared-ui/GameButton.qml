import QtQuick

// 统一按钮：支持鼠标点击、键盘/脑控聚焦、禁用状态
// 视觉对齐宿主 FluentWinUI3 / balance 样例：深色底、灰白字、薄荷绿高亮
Rectangle {
    id: root

    required property var theme
    property string text: ""
    property bool highlighted: false
    property bool dimmed: false
    property var onClicked: function() {}

    signal clicked()

    width: Math.max(96, buttonText.width + 32)
    height: 32
    radius: theme.buttonRadius

    color: {
        if (dimmed) return theme.panel
        if (highlighted) {
            if (mouseArea.pressed) return theme.primaryPressed
            if (mouseArea.containsMouse) return theme.primaryHover
            return theme.primary
        }
        if (mouseArea.pressed) return Qt.darker(theme.panel, 1.3)
        if (mouseArea.containsMouse) return Qt.lighter(theme.panel, 1.15)
        return theme.panel
    }

    border.color: highlighted ? theme.primary : theme.panelBorder
    border.width: 1

    Text {
        id: buttonText
        anchors.centerIn: parent
        text: root.text
        color: {
            if (dimmed) return theme.disabledText
            if (highlighted) return theme.background
            return theme.primaryText
        }
        font.pixelSize: theme.bodyPx
        font.family: root.theme.fontFamily
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: !dimmed
        onClicked: {
            root.onClicked()
            root.clicked()
        }
    }

    Behavior on color { ColorAnimation { duration: 100 } }
}
