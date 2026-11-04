import QtQuick
import "../shared-ui" as SharedUI

Item {
    id: root
    required property var taskContext
    required property var game

    SharedUI.GameTheme { id: theme }

    SharedUI.GameFrame {
        anchors.fill: parent
        theme: theme
        title: qsTr("SharedUI 导入测试")
        subtitle: qsTr("如果看到此外框，说明公共组件导入成功")
        mode: qsTr("测试模式")
        inputSource: (game && game.inputSource) ? game.inputSource : "local"

        SharedUI.GameButton {
            anchors.centerIn: parent
            theme: theme
            text: qsTr("测试按钮")
            highlighted: true
            onClicked: {
                game.record("shared-ui-test.button_clicked", {elapsed: game.elapsedSeconds})
            }
        }
    }

    Connections {
        target: root.game
        function onStarted() { game.record("shared-ui-test.started", {}) }
        function onStep(seconds) {}
        function onAction(name, pressed) {}
        function onPaused() {}
        function onResumed() {}
        function onStopping() {}
    }
}
