import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "hanoi"
    readonly property string version: "0.3.0"
    readonly property string title: qsTr("汉诺塔")
    readonly property string description: qsTr("规划与操作序列任务。2/3/4/5 盘可选；鼠标点击柱独立取放；键盘/脑控左右+确认；放回原柱计为取消不算步；大盘压小盘被拒绝。BCI 使用 GamepadLite。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
