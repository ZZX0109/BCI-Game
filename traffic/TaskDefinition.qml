import QtQml

QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "traffic"
    readonly property string version: "0.5.0"
    readonly property string title: qsTr("红绿灯过马路")
    readonly property string description: qsTr("信号路口观察与过街。红灯车辆通行，清场后行人绿灯亮起，车辆在停止线外排队；按住前进/后退，松开停止，独立脑控半车道步进。五关逐步增加车道、车速和大车，种子车流与世界坐标碰撞可追溯。")
    readonly property string entryPoint: "Main.qml"
    readonly property string icon: "assets/icon.svg"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
