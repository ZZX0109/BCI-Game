import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "target"
    readonly property string version: "0.3.0"
    readonly property string title: qsTr("精准打靶")
    readonly property string description: qsTr("指针定位与触发任务 V3。明确区分射击（target）与追踪（pursuit）：静态8靶 / Fitts 大小×距离 / 动态靶 / 遮挡靶四模式；首动阈值排除宿主初始同步；点击当帧判定；反馈定格 0.5s；遮挡挡板种子化可复现。BCI 使用 Cursor。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 1
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
