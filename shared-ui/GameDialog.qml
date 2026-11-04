import QtQuick

// 统一对话框：暂停、确认、结果提示
Rectangle {
    id: root

    required property var theme
    property string title: ""
    property string message: ""
    property var buttons: [] // [{text, highlighted, action}]

    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.55)
    visible: false
    opacity: 0
    z: 100

    MouseArea {
        anchors.fill: parent
        // 点击遮罩不关闭，必须通过按钮关闭
    }

    Rectangle {
        anchors.centerIn: parent
        width: 440
        height: dialogColumn.height + 48
        radius: theme.dialogRadius
        color: theme.panel
        border.color: theme.panelBorder
        border.width: 2

        Column {
            id: dialogColumn
            anchors.centerIn: parent
            width: parent.width - 48
            spacing: 20

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.title
                color: theme.primaryText
                font.pixelSize: theme.headingPx
                font.family: theme.fontFamily
                font.bold: true
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: root.message !== ""
                text: root.message
                color: theme.secondaryText
                font.pixelSize: theme.bodyPx
                font.family: theme.fontFamily
                wrapMode: Text.WordWrap
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16

                Repeater {
                    model: root.buttons
                    GameButton {
                        required property var modelData
                        theme: root.theme
                        text: modelData.text
                        highlighted: !!modelData.highlighted
                        onClicked: {
                            if (modelData.action) modelData.action()
                        }
                    }
                }
            }
        }
    }

    function open() {
        visible = true
        opacity = 1
    }

    function close() {
        opacity = 0
        closeTimer.start()
    }

    Timer {
        id: closeTimer
        interval: 200
        onTriggered: root.visible = false
    }

    Behavior on opacity { NumberAnimation { duration: 180 } }
}
