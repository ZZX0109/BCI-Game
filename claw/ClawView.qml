import QtQuick
import "../shared-ui" as SharedUI

Item {
    id: view
    SharedUI.GameTheme { id: uiTheme }
    required property var simulation
    property bool sideView: false
    readonly property real rail: sideView ? 52 : 64
    readonly property real floor: height - 42
    readonly property real innerLeft: sideView ? 22 : 38
    readonly property real innerRight: sideView ? width - 22 : width - 154
    function project(value) {
        var low = sideView ? simulation.zMin : simulation.xMin
        var high = sideView ? simulation.zMax : simulation.xMax
        // Reserve a stable delivery bay at every viewport width, outside the playable X range.
        if (!sideView && value > high)
            return innerRight + (value - high) / (simulation.dropX - high) * (width - 52 - innerRight)
        return innerLeft + (value - low) / (high - low) * (innerRight - innerLeft)
    }
    readonly property real clawPX: project(sideView ? simulation.clawZ : simulation.clawX)
    readonly property real progress: Math.max(0, Math.min(1, (simulation.clawY - simulation.clawTopY) / (simulation.floorY - 66 - simulation.clawTopY)))
    readonly property real detailScale: sideView ? 1 : Math.max(1, Math.min(1.4, height / 428))
    readonly property real toyScale: sideView ? 0.68 : detailScale
    readonly property real toyHeight: 58 * toyScale
    readonly property real clawPY: rail + 17 + progress * (floor - toyHeight - 28 * detailScale - rail - 17)
    readonly property real binX: sideView ? clawPX : project(simulation.dropX)

    Text { font.family: uiTheme.fontFamily; x: 0; y: 0; text: view.sideView ? qsTr("02  /  侧视") : qsTr("01  /  正视"); color: "#a4ad9c"; font.pixelSize: 14; font.letterSpacing: 1 }
    Text { font.family: uiTheme.fontFamily; anchors.right: parent.right; y: 1; text: view.sideView ? qsTr("前后位置") : qsTr("左右位置"); color: "#929b89"; font.pixelSize: 14 }

    // Open rail, with discrete fasteners and a restrained brushed-metal face.
    Rectangle { x: 0; y: view.rail - 6; width: parent.width; height: 11; radius: 2; color: "#393e35" }
    Rectangle { x: 0; y: view.rail - 6; width: parent.width; height: 2; color: "#a4ac9a" }
    Rectangle { x: 0; y: view.rail + 2; width: parent.width; height: 2; color: "#191c16" }
    Repeater {
        model: view.sideView ? 3 : 7
        Rectangle {
            required property int index
            x: 10 + index * (view.width - 24) / (view.sideView ? 2 : 6); y: view.rail - 2
            width: 3; height: 3; radius: 2; color: "#848b7c"
        }
    }
    // Axis marks and contact shadow keep the stage legible without a surrounding panel.
    Rectangle { x: 0; y: view.floor + 3; width: parent.width; height: 1; color: "#52584b" }
    Rectangle { x: 0; y: view.floor + 4; width: parent.width; height: 8; color: "#10130e" }
    Repeater {
        model: 9
        Rectangle {
            required property int index
            x: view.innerLeft + index * (view.innerRight - view.innerLeft) / 8
            y: view.floor + 4; width: 1; height: index % 2 ? 4 : 7; color: "#4c5345"
        }
    }
    Repeater {
        model: simulation.phase === "aligning" ? 11 : 0
        Rectangle {
            required property int index
            x: view.clawPX; y: view.rail + 52 + index * Math.max(1, (view.floor - view.rail - 62) / 11)
            width: 1; height: 4; color: "#8da77d"; opacity: 0.38
        }
    }
    Rectangle {
        visible: !view.sideView
        x: view.binX - 41; y: view.floor - 83; width: 82; height: 87
        color: "#0c130c"; border.color: "#556c4d"; border.width: 1
        Rectangle { x: -5; y: 0; width: 92; height: 7; color: "#6c825e" }
        Rectangle { x: 5; y: 7; width: 72; height: 56; color: "#050805" }
        Text { font.family: uiTheme.fontFamily; anchors.horizontalCenter: parent.horizontalCenter; y: 66; text: qsTr("取物口"); color: "#acbc9d"; font.pixelSize: 12; font.letterSpacing: 2 }
    }
    Rectangle {
        visible: simulation.toyState === "floor"
        x: view.project(view.sideView ? simulation.toyFloorZ : simulation.toyFloorX) - 34 * view.toyScale
        y: view.floor - 3; width: 68 * view.toyScale; height: 8; radius: width / 2
        color: "#493923"; opacity: 0.5
    }
    // One plush renderer per projection, both derived from the shared physical state.
    Item {
        id: toy
        readonly property bool attached: simulation.toyState === "attached"
        readonly property bool binned: simulation.toyState === "binned"
        readonly property real releaseT: simulation.phase === "release" ? Math.min(1, simulation.phaseTimer / 0.5) : 0
        visible: !(view.sideView && binned)
        x: (attached ? view.clawPX : binned ? view.binX : view.project(view.sideView ? simulation.toyFloorZ : simulation.toyFloorX)) - 26 * view.toyScale
        y: binned ? view.floor - view.toyHeight : attached ? view.clawPY + 28 * view.detailScale + releaseT * (view.floor - view.toyHeight - view.clawPY - 28 * view.detailScale) : view.floor - view.toyHeight
        width: 52; height: 58; scale: view.toyScale; transformOrigin: Item.TopLeft
        Rectangle { x: 3; y: 1; width: 16; height: 17; radius: 8; color: "#b7813c"; border.color: "#ddaf61"; Rectangle { x: 4; y: 4; width: 8; height: 9; radius: 5; color: "#764f2e" } }
        Rectangle { x: 33; y: 1; width: 16; height: 17; radius: 8; color: "#b7813c"; border.color: "#ddaf61"; Rectangle { x: 4; y: 4; width: 8; height: 9; radius: 5; color: "#764f2e" } }
        Rectangle { x: 7; y: 28; width: 38; height: 28; radius: 15; color: "#b7813c" }
        Rectangle { x: 2; y: 30; width: 12; height: 20; radius: 6; rotation: 24; color: "#d6a759" }
        Rectangle { x: 38; y: 30; width: 12; height: 20; radius: 6; rotation: -24; color: "#c49750" }
        Rectangle { x: 10; y: 47; width: 14; height: 11; radius: 5; color: "#dfa95c" }
        Rectangle { x: 28; y: 47; width: 14; height: 11; radius: 5; color: "#c69247" }
        Rectangle { x: 18; y: 32; width: 17; height: 19; radius: 9; color: "#f0ce8b" }
        Rectangle {
            x: 6; y: 7; width: 40; height: 32; radius: 15
            gradient: Gradient { GradientStop { position: 0; color: "#f6d594" } GradientStop { position: 1; color: "#cb9146" } }
            border.color: "#e0b46a"
            Rectangle { x: 8; y: 10; width: 5; height: 6; radius: 3; color: "#2b2117"; Rectangle { x: 1; y: 1; width: 2; height: 2; radius: 1; color: "#fbefda" } }
            Rectangle { x: 27; y: 10; width: 5; height: 6; radius: 3; color: "#2b2117"; Rectangle { x: 1; y: 1; width: 2; height: 2; radius: 1; color: "#fbefda" } }
            Rectangle { x: 12; y: 17; width: 17; height: 11; radius: 6; color: "#f2d5a3" }
            Rectangle { x: 17; y: 17; width: 7; height: 5; radius: 3; color: "#4c3521" }
            Rectangle { x: 20; y: 21; width: 1; height: 4; color: "#815b38" }
        }
        Rectangle { x: 15; y: 35; width: 22; height: 3; radius: 1; color: "#7e9e72" }
    }
    // Twin cable and articulated steel jaws.
    Rectangle { x: view.clawPX - 19; y: view.rail - 10; width: 38; height: 20; radius: 3; color: "#aeb8a6"; border.color: "#e4e8d9" }
    Rectangle { x: view.clawPX - 12; y: view.rail - 6; width: 24; height: 11; radius: 2; color: "#343e31" }
    Rectangle { x: view.clawPX - 3; y: view.rail + 10; width: 2; height: Math.max(0, view.clawPY - view.rail - 10); color: "#b0b7a5" }
    Rectangle { x: view.clawPX + 2; y: view.rail + 10; width: 1; height: Math.max(0, view.clawPY - view.rail - 10); color: "#5d6655" }
    Item {
        x: view.clawPX; y: view.clawPY
        scale: view.detailScale; transformOrigin: Item.TopLeft
        Rectangle { x: -20; y: 0; width: 40; height: 17; radius: 5; gradient: Gradient { GradientStop { position: 0; color: "#f0f1e5" } GradientStop { position: 0.4; color: "#a9b29f" } GradientStop { position: 1; color: "#5b6651" } } }
        Rectangle { x: -8; y: -5; width: 16; height: 8; radius: 2; color: "#858f79" }
        Rectangle { x: -17; y: 10; width: 6; height: 25; radius: 2; color: "#c5ceba"; rotation: simulation.toyState === "attached" ? -16 : 22; transformOrigin: Item.Top; Rectangle { x: 0; y: 21; width: 11; height: 5; radius: 2; color: "#d7dfcc" } }
        Rectangle { x: 11; y: 10; width: 6; height: 25; radius: 2; color: "#a6b398"; rotation: simulation.toyState === "attached" ? 16 : -22; transformOrigin: Item.Top; Rectangle { x: -5; y: 21; width: 11; height: 5; radius: 2; color: "#c3cfb5" } }
        Rectangle { x: -16; y: 9; width: 4; height: 4; radius: 2; color: "#424c39" }
        Rectangle { x: 12; y: 9; width: 4; height: 4; radius: 2; color: "#424c39" }
    }
    Text { font.family: uiTheme.fontFamily; x: 0; y: view.height - 19; text: view.sideView ? qsTr("后 ↑") : qsTr("← 左"); color: "#89927e"; font.pixelSize: 13 }
    Text { font.family: uiTheme.fontFamily; anchors.right: parent.right; y: view.height - 19; text: view.sideView ? qsTr("↓ 前") : qsTr("右 →"); color: "#89927e"; font.pixelSize: 13 }
}
