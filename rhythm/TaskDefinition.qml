import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "rhythm"
    readonly property string version: "1.3.0"
    readonly property string title: qsTr("四向律动")
    readonly property string description: qsTr("三轮方向与保持训练；可选教学、标准或挑战节奏，分别控制音符间隔与判定窗。提供可独立开关的原创背景音乐、节拍提示音与反馈音效。BCI输入默认使用教学速度，需按解码时序单独校准。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
