import QtQml

QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "traffic"
    readonly property string version: "0.3.0"
    readonly property string title: qsTr("红绿灯过马路")
    readonly property string description: qsTr("Go/No-Go 与第一人称过街情境双模式 V3。go_nogo 保留离散信号判断；crossing_decision 提供第一人称/近第一人称道路过街，种子化可复现车流，支持碰撞事故判定。记录四类结果与反应时。effector=2。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
