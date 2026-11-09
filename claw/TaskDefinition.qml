import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "claw"
    readonly property string version: "0.4.1"
    readonly property string title: qsTr("抓娃娃机")
    readonly property string description: qsTr("正视主画面与左上侧视图，共享X/Z定位和高度。方向键定位；键盘仅Enter触发抓取（Space不抓取），GamepadLite confirm仍有效。按触发瞬间的二维误差判定，并自动完成投放。")
    readonly property string entryPoint: "Main.qml"
    readonly property string icon: "assets/icon.svg"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
