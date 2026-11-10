import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "pointer"
    readonly property string version: "1.1.0"
    readonly property string title: qsTr("目标控制训练")
    readonly property string description: qsTr("一个入口，持续追踪与精准打靶两套独立任务。子任务分别记录与评分，可返回选择；结束本次会话时仅提交一次汇总，保持 pursuit/target 原事件及历史指标。")
    readonly property string entryPoint: "Main.qml"
    readonly property string icon: "assets/icon.svg"
    readonly property int effector: 1
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
