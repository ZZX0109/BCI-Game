import QtQuick
import "../shared-ui" as SharedUI

// London Tower piece. A separate sphere visual keeps Hanoi discs unchanged.
Item {
    id: ball
    property color tint: "#c86d67"
    property string mark: "R"
    property bool lifted: false
    SharedUI.GameTheme { id: theme }
    Rectangle {
        x: 5; y: parent.height - 8; width: parent.width - 10; height: ball.lifted ? 15 : 9
        radius: height / 2; color: "#000000"; opacity: ball.lifted ? .4 : .28
    }
    Rectangle {
        x: 0; y: 0; width: Math.min(parent.width, parent.height); height: width
        anchors.horizontalCenter: parent.horizontalCenter; radius: width / 2
        border.width: 1; border.color: Qt.lighter(ball.tint, 1.4)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(ball.tint, 1.45) }
            GradientStop { position: .4; color: ball.tint }
            GradientStop { position: 1; color: Qt.darker(ball.tint, 1.65) }
        }
        Rectangle { x: parent.width*.22; y: parent.height*.13; width: parent.width*.3; height: parent.height*.16; radius: height/2; rotation: -25; color: "#60ffffff" }
        Text { anchors.centerIn: parent; text: ball.mark; color: "#f5f5ef"; font.family: theme.fontFamily; font.pixelSize: 14; font.bold: true }
    }
}
