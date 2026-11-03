import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "pursuit"
    readonly property string version: "0.3.0"
    readonly property string title: qsTr("追光球")
    readonly property string description: qsTr("连续追踪任务 V3。二维全屏自由追踪 + 多关卡（椭圆/8字/自由巡游/遮挡恢复）+ 多轮制；保留 1D 教学正弦模式。MAE/RMSE/区内占比/最长保持/连续保持指标；确定性时间函数轨迹。BCI 使用 Cursor。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 1
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
