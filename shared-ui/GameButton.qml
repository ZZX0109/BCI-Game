import QtQuick

// 统一按钮：透明底 + 米白描边（pong 语言），高亮时薄荷绿填充
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
        if (dimmed) return Qt.rgba(1, 1, 1, 0.04)
        if (highlighted) {
            if (mouseArea.pressed) return theme.primaryPressed
            if (mouseArea.containsMouse) return theme.primaryHover
            return theme.primary
        }
        if (mouseArea.pressed) return Qt.rgba(1, 1, 1, 0.12)
        if (mouseArea.containsMouse) return Qt.rgba(1, 1, 1, 0.07)
        return "transparent"
    }

    border.color: highlighted ? theme.primary : (dimmed ? theme.disabledText : theme.secondaryText)
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
