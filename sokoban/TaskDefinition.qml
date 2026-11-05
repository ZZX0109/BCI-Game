import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "sokoban"
    readonly property string version: "0.4.1"
    readonly property string title: qsTr("推箱子")
    readonly property string description: qsTr("五关 BFS 验证关卡（S01–S05）。纯鼠标/键盘/脑控独立完成：点击相邻格或方向按钮移动，撤销、重开、菜单。静态墙角死局保留进度，等待主动恢复。撞墙与推箱受阻分开统计。BCI 使用 GamepadLite。")
    readonly property string entryPoint: "Main.qml"
    readonly property string icon: "assets/icon.svg"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
