import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "pursuit"
    readonly property string version: "0.5.1"
    readonly property string title: qsTr("追光球")
    readonly property string description: qsTr("连续追踪任务。三轮种子化随机平滑追踪，25 秒/轮、自动推进、无选关：R1 基础自由 / R2 连续变速 / R3 复杂变速与遮挡。目标由确定性 targetAt(round,time,seed) 生成，X/Y 均参与；评分按整段可见轨迹 MAE/RMSE/区内占比/重捕获，遮挡段误差单列；不实时显示误差数值。BCI 使用 Cursor。")
    readonly property string entryPoint: "Main.qml"
    readonly property string icon: "assets/icon.svg"
    readonly property int effector: 1
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
