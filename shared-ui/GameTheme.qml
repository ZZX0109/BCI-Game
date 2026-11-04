import QtQuick

// Neuralife 共享主题令牌
// 依据宿主真实样例 balance/Main.qml 与 pong/Main.qml 的实代码取色：
//   场景背景 #050505、前景 #f5f5ef、成功 #80ff9b、警告 #ffdf70、字体 Segoe UI。
// themeIndex: 0=Dark（默认，对齐官方样例）, 1=Mint, 2=Light（占位，待宿主暴露后接入）
// 宿主当前未暴露主题信号（game 对象仅含 elapsedSeconds/finish/inputSource/record/width/height），
// 故默认固定 Dark。待宿主提供 themeIndex 或 colorScheme 后，在此处接入即可。
QtObject {
    id: tokens

    property int themeIndex: 0
    readonly property bool isDark: themeIndex === 0
    readonly property bool isMint: themeIndex === 1
    readonly property bool isLight: themeIndex === 2

    readonly property color background: "#050505"
    readonly property color sceneBackground: "#050505"
    readonly property color panel: "#121212"
    readonly property color panelBorder: "#333333"

    readonly property color primary: "#80ff9b"          // 成功/目标/进度
    readonly property color primaryHover: "#9dffb3"
    readonly property color primaryPressed: "#66cc7d"

    readonly property color warning: "#ffdf70"          // 时间/警告/高亮
    readonly property color warningHover: "#ffe88f"
    readonly property color warningPressed: "#ccb35a"

    readonly property color danger: "#ff6b6b"           // 错误/死局/碰撞
    readonly property color dangerHover: "#ff8585"
    readonly property color dangerPressed: "#cc5555"

    readonly property color info: "#80ff9b"             // 与 success 共用

    readonly property color primaryText: "#f5f5ef"      // 主文字
    readonly property color secondaryText: "#8f938e"    // 次要文字
    readonly property color disabledText: "#505450"     // 禁用文字

    readonly property color success: primary
    readonly property color failure: danger

    readonly property string fontFamily: "Segoe UI"

    readonly property int titlePx: 28
    readonly property int headingPx: 22
    readonly property int bodyPx: 16
    readonly property int captionPx: 14

    readonly property int frameTopHeight: 72
    readonly property int frameBottomHeight: 64
    readonly property int dialogRadius: 8
    readonly property int buttonRadius: 4
}
