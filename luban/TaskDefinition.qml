import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "luban"
    readonly property string version: "0.4.0"
    readonly property string title: qsTr("鲁班锁")
    readonly property string description: qsTr("真实三维互锁机关 V4。Qt Quick 3D 渲染 + 射线拾取；木件为盒体并集，可见几何即碰撞几何，榫槽与凹槽是实体不是贴图。抽出是否可行完全由体素重叠实时判定，不查预设顺序表。三关：教学三件交叉 / 基础四件互锁 / 经典六件（起始锁 3 件）。支持旋转观察、点选、方向按钮与拖动抽出、撤销、复位；键盘与 GamepadLite 脑控可通过模式选择完成全流程。启动需 RHI 渲染后端（play.bat 对 luban 自动设置）。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
