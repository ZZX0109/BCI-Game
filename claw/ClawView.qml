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
    readonly property real innerRight: sideView ? width - 22 : width - Math.min(154, width * 0.24)
    function project(value) {
        var low = sideView ? simulation.zMin : simulation.xMin
        var high = sideView ? simulation.zMax : simulation.xMax
        // Reserve a stable delivery bay at every viewport width, outside the playable X range.
        if (!sideView && value > high)
            return innerRight + (value - high) / (simulation.dropX - high) * (width - 52 - innerRight)
        return innerLeft + (value - low) / (high - low) * (innerRight - innerLeft)
    }
    readonly property real clawPX: project(sideView ? simulation.clawZ : simulation.clawX)
    readonly property real progress: Math.max(0, Math.min(1, (simulation.clawY - simulation.clawTopY) / (simulation.contactY - simulation.clawTopY)))
    readonly property real detailScale: sideView ? 1 : Math.max(1, Math.min(2.0, height / 390))
    readonly property real toyScale: (sideView ? 0.68 : detailScale) * simulation.targetSize
    readonly property real toyHeight: 58 * toyScale
    readonly property real clawPY: rail + 17 + progress * (floor - toyHeight - 28 * detailScale - rail - 17)
    readonly property real binX: sideView ? clawPX : project(simulation.dropX)

    Text { font.family: uiTheme.fontFamily; x: 0; y: 0; text: view.sideView ? qsTr("02  /  Z 侧视") : qsTr("01  /  X 正视"); color: "#a4ad9c"; font.pixelSize: 14; font.letterSpacing: 1 }
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
    // Non-target objects use the same X/Z projection; their shape never changes the target.
    Repeater {
        model: simulation.distractors
        Rectangle {
            required property var modelData
            x: view.project(view.sideView ? modelData.z : modelData.x) - width / 2
            y: view.floor - height
            width: (view.sideView ? 26 : 42); height: width
            radius: modelData.kind === "ball" ? width / 2 : 5
            color: "#566e77"; border.color: "#93a6ab"; opacity: 0.8
            Text { anchors.centerIn: parent; text: "×"; color: "#b4c1c2"; font.pixelSize: 18 }
        }
    }
    // One target renderer per projection; no separate floor/carried toy copies.
    Item {
        id: toy
        objectName: view.sideView ? "clawSideTarget" : "clawFrontTarget"
        readonly property bool attached: simulation.toyState === "attached"
        readonly property bool binned: simulation.toyState === "binned"
        readonly property bool nearMiss: simulation.toyState === "near_miss"
        readonly property real nearProgress: simulation.phase === "partial_lift" ? Math.min(1, simulation.phaseTimer / .35)
            : simulation.phase === "slip" ? Math.max(0, 1 - simulation.phaseTimer / .35) : 0
        readonly property real releaseT: simulation.phase === "release" ? Math.min(1, simulation.phaseTimer / 0.5) : 0
        visible: !(view.sideView && binned)
        x: (attached ? view.clawPX : binned ? view.binX : view.project(view.sideView ? simulation.toyFloorZ : simulation.toyFloorX)) - 26 * view.toyScale
        y: binned ? view.floor - view.toyHeight : attached ? view.clawPY + 28 * view.detailScale + releaseT * (view.floor - view.toyHeight - view.clawPY - 28 * view.detailScale) : view.floor - view.toyHeight - (nearMiss ? nearProgress * simulation.nearLiftHeight * 120 * view.toyScale : 0)
        width: 52; height: 58; scale: view.toyScale; transformOrigin: Item.TopLeft
        rotation: nearMiss ? simulation.tiltDirection * (simulation.phase === "partial_lift" ? Math.min(1, simulation.phaseTimer / .2) : nearProgress) : 0
        Rectangle {
            x: 0; y: 6; width: 52; height: 52
            radius: simulation.targetKind === "ball" ? 26 : 7
            gradient: Gradient {
                GradientStop { position: 0; color: "#ffe4a0" }
                GradientStop { position: 0.5; color: "#edb854" }
                GradientStop { position: 1; color: "#a66b29" }
            }
            border.color: "#ffdd90"; border.width: 1.5
            Rectangle { x: 8; y: 7; width: 20; height: 10; radius: 5; rotation: -20; color: "#fff6cf"; opacity: 0.5 }
            Rectangle { x: 14; y: 24; width: 5; height: 6; radius: 3; color: "#59452c" }
            Rectangle { x: 33; y: 24; width: 5; height: 6; radius: 3; color: "#59452c" }
            Rectangle { x: 22; y: 36; width: 9; height: 2; radius: 1; color: "#72502b" }
        }
    }
    // Partial foreground obstruction belongs to the trial plan, identically projected in both views.
    Rectangle {
        visible: simulation.occluder !== null && simulation.toyState === "floor"
        x: simulation.occluder ? view.project(view.sideView ? simulation.occluder.z : simulation.occluder.x) - width / 2 : 0
        y: view.floor - height
        width: view.sideView ? 22 : 36; height: view.sideView ? 22 : 34
        radius: 3; color: "#41483c"; border.color: "#7a846e"
        Rectangle { anchors.centerIn: parent; width: parent.width - 6; height: 2; rotation: -35; color: "#68715b" }
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
