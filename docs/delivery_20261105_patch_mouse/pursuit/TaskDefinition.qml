import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "pursuit"
    readonly property string version: "0.5.2"
    readonly property string title: qsTr("追光球")
    readonly property string description: qsTr("连续追踪任务。固定五轮二维自由追踪，25 秒/轮、自动推进、无选关：R1 直线宽转弯 / R2 椭圆 / R3 8字 / R4 种子化平滑自由轨迹 / R5 自由轨迹+遮挡。目标由确定性 targetAt(round,time,seed) 生成，X/Y 均参与；评分按整段可见轨迹 MAE/RMSE/区内占比/重捕获，遮挡段误差单列；不实时显示误差数值。BCI 使用 Cursor。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 1
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
