import QtQuick
import "../shared-ui" as SharedUI

// A shallow cylinder. Geometry/hit area stays in Main.qml; this is purely visual.
Item {
    id: disc
    SharedUI.GameTheme { id: uiTheme }
    property color tint: "#c8aa70"
    property int number: 1
    property string label: ""
    property bool lifted: false
    property bool ball: false
    height: ball ? 54 : 34
    Rectangle {
        x: 5; y: disc.ball ? 48 : (disc.lifted ? 43 : 27)
        width: parent.width - 10; height: disc.lifted ? 18 : 12
        radius: width / 2
        color: "#000000"; opacity: disc.lifted ? 0.45 : 0.65
    }
    Rectangle {
        visible: !disc.ball
        x: 0; y: 8; width: parent.width; height: 20
        radius: 8
        gradient: Gradient {
            GradientStop { position: 0; color: disc.tint }
            GradientStop { position: 1; color: Qt.darker(disc.tint, 1.9) }
        }
    }
    Rectangle {
        visible: !disc.ball
        x: 0; y: 21; width: parent.width; height: 13
        radius: width / 2
        color: Qt.darker(disc.tint, 1.65)
        border.width: 1; border.color: Qt.darker(disc.tint, 1.3)
    }
    Rectangle {
        visible: !disc.ball
        x: 0; y: 0; width: parent.width; height: 17
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(disc.tint, 1.28) }
            GradientStop { position: 1; color: disc.tint }
        }
        border.width: 1; border.color: Qt.lighter(disc.tint, 1.45)
    }
    Rectangle {
        visible: !disc.ball
        x: 15; y: 4; width: parent.width - 30; height: 6
        radius: width / 2
        color: "transparent"; border.width: 1; border.color: "#25ffffff"
    }
    LondonBall {
        visible: disc.ball
        anchors.fill: parent
        tint: disc.tint
        mark: disc.label
        lifted: disc.lifted
    }
    Text { visible: !disc.ball; font.family: uiTheme.fontFamily;
        anchors.horizontalCenter: parent.horizontalCenter
        y: disc.ball ? 18 : 14; text: disc.label !== "" ? disc.label : disc.number
        color: "#f5f5ef"; opacity: 0.95
        font.pixelSize: 12; font.weight: Font.DemiBold
    }
}
