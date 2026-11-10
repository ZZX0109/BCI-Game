import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "luban"
    readonly property string version: "0.7.0"
    readonly property string title: qsTr("鲁班锁")
    readonly property string description: qsTr("真实三维鲁班锁：选中编号木件，沿长轴 A / B 两端拆解。支持鼠标点选、等比例拖动、观察旋转，以及上下左右和确认的完整脑控流程；几何碰撞决定阻挡，支持撤销和复位。前三关教学，后两关偏移槽/六件分支机关需部分滑动与反向推回；支持微移、单件榫槽观察和三级主动提示。需 Qt Quick 3D 与 RHI 图形后端。")
    readonly property string entryPoint: "Main.qml"
    readonly property string icon: "assets/icon.svg"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
