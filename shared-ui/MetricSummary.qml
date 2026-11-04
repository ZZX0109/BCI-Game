import QtQuick

// 回合/会话结算面板：只展示关键指标，详细数据放 JSONL
Rectangle {
    id: root

    required property var theme
    property string title: ""
    property var metrics: [] // [{label, value, color}]
    property string hint: ""

    anchors.centerIn: parent
    width: 420
    height: contentColumn.height + 48
    radius: theme.dialogRadius
    color: theme.panel
    border.color: theme.panelBorder
    border.width: 2
    visible: false
    opacity: 0

    Column {
        id: contentColumn
        anchors.centerIn: parent
        width: parent.width - 48
        spacing: 14

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.title
            color: theme.primaryText
            font.pixelSize: theme.headingPx
            font.family: theme.fontFamily
            font.bold: true
        }

        Repeater {
            model: root.metrics
            Rectangle {
                width: parent.width
                height: metricLabel.height + 8
                color: "transparent"
                Text {
                    id: metricLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: theme.secondaryText
                    font.pixelSize: theme.bodyPx
                    font.family: theme.fontFamily
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.value
                    color: modelData.color || theme.primaryText
                    font.pixelSize: theme.bodyPx
                    font.family: theme.fontFamily
                    font.bold: true
                }
            }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: root.hint !== ""
            text: root.hint
            color: theme.secondaryText
            font.pixelSize: theme.captionPx
            font.family: theme.fontFamily
            wrapMode: Text.WordWrap
        }
    }

    function show() {
        visible = true
        opacity = 1
    }

    function hide() {
        opacity = 0
        hiddenTimer.start()
    }

    Timer {
        id: hiddenTimer
        interval: 200
        onTriggered: root.visible = false
    }

    Behavior on opacity { NumberAnimation { duration: 180 } }
}
