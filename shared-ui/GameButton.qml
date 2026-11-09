import QtQuick

Rectangle {
    id: root
    required property var theme
    property string text: ""
    property bool highlighted: false
    property bool dimmed: false
    property bool keyDown: false
    signal clicked()
    signal pressed()
    signal released()
    implicitWidth: Math.max(96, buttonText.implicitWidth + 32)
    implicitHeight: 44
    width: implicitWidth
    height: implicitHeight
    radius: theme.buttonRadius
    activeFocusOnTab: enabled && !dimmed && visible
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: root.activate()
    opacity: dimmed || !enabled ? 0.48 : 1
    color: highlighted ? ((mouseArea.pressed || keyDown) ? theme.primaryPressed : (mouseArea.containsMouse ? theme.primaryHover : theme.primary))
                       : ((mouseArea.pressed || keyDown) ? "#34454b" : (mouseArea.containsMouse ? "#26353b" : theme.panel))
    border.color: activeFocus ? theme.warning : (highlighted ? theme.primary : theme.panelBorder)
    border.width: activeFocus ? 2 : 1
    function activate() { if (enabled && !dimmed && visible) root.clicked() }
    onDimmedChanged: if (dimmed) { keyDown = false; focus = false }
    Text {
        id: buttonText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - 16)
        text: root.text
        color: root.highlighted ? root.theme.background : root.theme.primaryText
        font.pixelSize: root.theme.bodyPx
        font.family: root.theme.fontFamily
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled && !root.dimmed
        cursorShape: Qt.PointingHandCursor
        onPressed: { root.forceActiveFocus(); root.pressed() }
        onReleased: root.released()
        onCanceled: root.released()
        onClicked: root.activate()
    }
    Keys.onPressed: function(event) {
        event.accepted = false
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            event.accepted = true
            if (!event.isAutoRepeat && !root.dimmed) { root.keyDown = true; root.pressed() }
        }
    }
    Keys.onReleased: function(event) {
        event.accepted = false
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            event.accepted = true
            if (root.keyDown && !event.isAutoRepeat) { root.keyDown = false; root.released(); root.activate() }
        }
    }
    onActiveFocusChanged: if (!activeFocus && keyDown) { keyDown = false; root.released() }
    Behavior on color { ColorAnimation { duration: 90 } }
}
