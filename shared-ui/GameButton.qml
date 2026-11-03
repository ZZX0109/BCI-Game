import QtQuick

// 统一按钮：支持鼠标点击、键盘/脑控聚焦、禁用状态
Rectangle {
    id: root

    required property var theme
    property string text: ""
    property bool highlighted: false
    property bool dimmed: false
    property var onClicked: function() {}

    signal clicked()

    width: Math.max(96, buttonText.width + 32)
    height: 40
    radius: theme.buttonRadius
    color: {
        if (dimmed) return theme.panel
        if (highlighted) return theme.primary
        return theme.panel
    }
    border.color: highlighted ? theme.primary : theme.panelBorder
    border.width: 2

    Text {
        id: buttonText
        anchors.centerIn: parent
        text: root.text
        color: {
            if (dimmed) return theme.disabledText
            if (highlighted) return "#FFFFFF"
            return theme.primaryText
        }
        font.pixelSize: theme.bodyPx
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.onClicked()
            root.clicked()
        }
    }

    Behavior on color { ColorAnimation { duration: 120 } }
}
