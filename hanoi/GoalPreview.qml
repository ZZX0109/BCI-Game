import QtQuick

// The task's fixed destination, never a live error or a suggested next move.
Item {
    id: root
    required property var stacks
    required property var capacities
    required property var theme
    property bool london: false
    property bool expanded: false
    Text {
        anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
        text: qsTr("目标示意"); color: root.theme.secondaryText
        font.family: root.theme.fontFamily; font.pixelSize: 13
    }
    Repeater {
        model: 3
        Item {
            id: peg
            required property int index
            readonly property var stack: root.stacks && root.stacks[index] ? root.stacks[index] : []
            readonly property int baseY: root.expanded ? 105 : 57
            readonly property int pitch: root.expanded ? 29 : 16
            x: index * root.width / 3; y: 20; width: root.width / 3; height: root.expanded ? 130 : 80
            Rectangle {
                x: parent.width / 2 - (root.expanded ? 3 : 2); y: peg.baseY - height; width: root.expanded ? 6 : 4
                height: root.london ? root.capacities[peg.index] * peg.pitch + 5 : (root.expanded ? 85 : 47)
                radius: 2; color: "#77817b"
            }
            Rectangle { x: 10; y: peg.baseY; width: parent.width - 20; height: 3; radius: 1.5; color: "#9c987f" }
            Repeater {
                model: peg.stack.length
                Rectangle {
                    required property int index
                    readonly property int piece: peg.stack[index]
                    width: root.london ? (root.expanded ? 27 : 14) : (root.expanded ? 18 + piece * 12 : 10 + piece * 7)
                    height: root.london ? (root.expanded ? 27 : 14) : (root.expanded ? 9 : 5)
                    x: peg.width / 2 - width / 2
                    y: peg.baseY - 1 - (index + 1) * (root.london ? peg.pitch : (root.expanded ? 11 : 7))
                    radius: root.london ? width / 2 : 2
                    color: root.london ? (piece === 3 ? "#c86d67" : piece === 2 ? "#75a987" : "#729fce") : "#c5a165"
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter; y: peg.baseY + 6
                text: ["A", "B", "C"][peg.index]
                color: root.theme.secondaryText; font.family: root.theme.fontFamily; font.pixelSize: 11
            }
        }
    }
}
