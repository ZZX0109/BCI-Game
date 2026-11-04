import QtQuick

// 根据输入源显示合适的操作说明
Text {
    id: root

    required property var theme
    property string source: "local" // local | bci | pointer
    property string action: ""
    property string keyboardHint: ""
    property string mouseHint: ""
    property string bciHint: ""

    color: theme.secondaryText
    font.pixelSize: theme.captionPx
    font.family: theme.fontFamily
    text: {
        if (source === "bci" && bciHint !== "") return bciHint
        if (source === "pointer" && mouseHint !== "") return mouseHint
        if (keyboardHint !== "") return keyboardHint
        if (mouseHint !== "") return mouseHint
        return action
    }
}
