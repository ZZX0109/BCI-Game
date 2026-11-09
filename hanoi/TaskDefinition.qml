import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "hanoi"
    readonly property string version: "1.0.0"
    readonly property string title: qsTr("汉诺塔与伦敦塔")
    readonly property string description: qsTr("五局序列任务：前三局为3/4/5盘汉诺塔，后两局为容量3/2/1的彩球伦敦塔。伦敦塔按目标排列完成，不使用大盘压小盘规则；鼠标、键盘与GamepadLite输入沿用同一交互状态机。")
    readonly property string entryPoint: "Main.qml"
    readonly property string icon: "assets/icon.svg"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
