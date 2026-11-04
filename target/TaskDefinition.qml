import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "target"
    readonly property string version: "0.4.0"
    readonly property string title: qsTr("精准打靶")
    readonly property string description: qsTr("指针定位与触发任务 V4。以靶场场景局部坐标为唯一权威：鼠标点=准星中心=射击判定点。静态8靶 / Fitts 大小×距离 / 动态靶 / 遮挡靶四模式；鼠标经真实 MouseArea 取局部坐标，宿主 onPointer 换算后供 Cursor；点击当帧判定、左右键去重；遮挡中的射击按配置不计命中并单独记录。BCI 使用 Cursor。")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 1
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
