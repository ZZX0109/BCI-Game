import QtQml

QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "traffic"
    readonly property string version: "0.5.1"
    readonly property string title: qsTr("红绿灯过马路")
    readonly property string description: qsTr("观察信号与持续车流，按住前进/后退并在松键时停止；键盘、屏幕按钮与GamepadLite均可操作。种子化车流和世界坐标碰撞可追溯，支持本地键盘焦点恢复及输入/模拟时间诊断。")
    readonly property string entryPoint: "Main.qml"
    readonly property string icon: "assets/icon.svg"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
