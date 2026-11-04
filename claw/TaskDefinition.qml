import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "claw"
    readonly property string version: "0.3.1"
    readonly property string title: qsTr("抓娃娃机")
    readonly property string description: qsTr("二维 X/Z 精度抓取：左右移动 X、上下移动 Z（前后），确认后下降接触。俯视+侧视双窗口；对齐阶段不提示方向、不对准变绿，误差数值仅在接触/结算后显示。成败由触发瞬间归一化几何误差决定。BCI 使用 GamepadLite。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
