import QtQml

QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "traffic"
    readonly property string version: "0.2.0"
    readonly property string title: qsTr("红绿灯过马路")
    readonly property string description: qsTr("Go/No-Go 多试次任务：绿灯按确认启动，红灯保持等待。8 试次固定序列，记录四类结果与反应时。红灯不操作 != 神经抑制成功。V2 为信号判断模式，与现实过街情境模式分离。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
