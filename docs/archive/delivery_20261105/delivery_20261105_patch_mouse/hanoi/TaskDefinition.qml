import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "hanoi"
    readonly property string version: "0.6.0"
    readonly property string title: qsTr("汉诺塔")
    readonly property string description: qsTr("规划与操作序列任务。固定五局 3/3/4/4/5，每局自动推进，仅第五局后结束会话；无选关界面。鼠标仅拖放顶盘；键盘左右选柱、上键取盘、下键放盘；脑控保留左右与确认取放协议，各自独立完成；放回原柱计为取消不算步；大盘压小盘被拒绝。BCI 使用 GamepadLite。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
