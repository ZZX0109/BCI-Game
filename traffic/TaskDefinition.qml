import QtQml

QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "traffic"
    readonly property string version: "0.4.0"
    readonly property string title: qsTr("红绿灯过马路")
    readonly property string description: qsTr("侧视/斜侧视街道躲车 V4。世界坐标真值 + 投影渲染：玩家按住左右持续前进/后退，多车道持续车流按各自方向与速度驶过，采用真实几何碰撞（不再以灯色判断通关），五关 C01–C05 难度递增（2→5 车道、车速与密度提升、C04 大车遮挡）。种子化车流可复现，失败同关快速重试。effector=2。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
