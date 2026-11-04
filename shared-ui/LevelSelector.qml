import QtQuick

// 关卡/难度选择器：支持鼠标点击、键盘/脑控左右选择+确认
Rectangle {
    id: root

    required property var theme
    property var levels: [] // [{id, label, description}]
    property int currentIndex: 0
    property string title: qsTr("选择关卡")

    anchors.centerIn: parent
    width: 520
    height: contentColumn.height + 48
    radius: theme.dialogRadius
    color: theme.panel
    border.color: theme.panelBorder
    border.width: 2

    Column {
        id: contentColumn
        anchors.centerIn: parent
        width: parent.width - 48
        spacing: 16

        Text {
            text: root.title
            color: theme.primaryText
            font.pixelSize: theme.headingPx
            font.family: theme.fontFamily
            font.bold: true
        }

        Repeater {
            model: root.levels
            Rectangle {
                width: parent.width
                height: 56
                radius: theme.buttonRadius
                color: index === root.currentIndex ? theme.primary : theme.background
                border.color: index === root.currentIndex ? theme.primary : theme.panelBorder
                border.width: 2

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: modelData.label
                        color: index === root.currentIndex ? theme.background : theme.primaryText
                        font.pixelSize: theme.bodyPx
                        font.family: theme.fontFamily
                        font.bold: true
                    }
                    Text {
                        visible: modelData.description !== undefined
                        text: modelData.description || ""
                        color: index === root.currentIndex ? theme.background : theme.secondaryText
                        font.pixelSize: theme.captionPx
                        font.family: theme.fontFamily
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.currentIndex = index
                }
            }
        }
    }

    function moveLeft() {
        if (currentIndex > 0) currentIndex--
    }
    function moveRight() {
        if (currentIndex < levels.length - 1) currentIndex++
    }
}
