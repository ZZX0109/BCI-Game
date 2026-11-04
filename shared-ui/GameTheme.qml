import QtQuick

// Neuralife V3 统一主题令牌
// themeIndex: 0=Light, 1=Mint, 2=Dark
// 宿主当前未暴露主题信号（game 对象仅含 elapsedSeconds/finish/inputSource/record/width/height），
// 故默认固定 Light。待宿主提供 themeIndex 或 colorScheme 后，在此处接入即可。
QtObject {
    id: tokens

    property int themeIndex: 0
    readonly property bool isLight: themeIndex === 0
    readonly property bool isMint: themeIndex === 1
    readonly property bool isDark: themeIndex === 2

    readonly property color background: isDark ? "#242A30" : (isLight ? "#F6F6F6" : "#F0F7F7")
    readonly property color panel: isDark ? "#333940" : (isLight ? "#EBEBEB" : "#E0EFEF")
    readonly property color panelBorder: isDark ? "#4A5568" : (isLight ? "#D7D7D7" : "#B8D0D0")

    readonly property color primary: isMint ? "#2E8C8C" : (isLight ? "#368B9C" : "#57B6B6")
    readonly property color primaryHover: isMint ? "#267575" : (isLight ? "#2D6F7D" : "#469E9E")
    readonly property color primaryPressed: isMint ? "#1E5E5E" : (isLight ? "#225560" : "#368282")

    readonly property color primaryText: isDark ? "#F5F5F5" : "#202B33"
    readonly property color secondaryText: isDark ? "#C0C0C0" : "#595959"
    readonly property color disabledText: isDark ? "#6B7280" : "#9CA3AF"

    readonly property color success: "#2E8C8C"
    readonly property color danger: "#C45353"
    readonly property color warning: "#B9822C"
    readonly property color info: "#368B9C"

    readonly property int titlePx: 26
    readonly property int headingPx: 20
    readonly property int bodyPx: 16
    readonly property int captionPx: 14

    readonly property int frameTopHeight: 72
    readonly property int frameBottomHeight: 64
    readonly property int dialogRadius: 12
    readonly property int buttonRadius: 8
}
