import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "rhythm"
    readonly property string version: "1.0.1"
    readonly property string title: qsTr("四向律动")
    readonly property string description: qsTr("五轮运动想象节奏训练：左右、四向、序列、保持和变速。GamepadLite方向命令，提前提示、可配置判定窗口、按住或脉冲续期两种保持方式。含本地原创节拍、动作示意和可追溯的指令表现日志。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
