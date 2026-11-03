import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "luban"
    readonly property string version: "0.3.0"
    readonly property string title: qsTr("鲁班锁 · 教学模型")
    readonly property string description: qsTr("四木块空间拆卸教学模型 V3。统一框架 + 增强 2.5D/伪 3D 榫卯视觉（真实 QtQuick3D 未部署，已记录 fallback）。选择/方向双独立判断；错误不改变拼图状态；合法顺序 ≥2 条。BCI 使用 GamepadLite。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
