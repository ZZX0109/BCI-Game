import QtQml

QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "traffic"
    readonly property string version: "0.6.1"
    readonly property string title: qsTr("红绿灯过马路")
    readonly property string description: qsTr("左向右穿越六条车道，在第三和第四车道间的安全岛观察车流；右键前进、左键撤退、松开停止。车流、碰撞和种子记录可复盘。")
    readonly property string entryPoint: "Main.qml"
    readonly property string icon: "assets/icon.svg"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
