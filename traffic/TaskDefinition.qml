import QtQml
QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "traffic"
    readonly property string version: "0.1.0"
    readonly property string title: qsTr("Traffic Light Crossing")
    readonly property string description: qsTr("Cross on green, stop on red. Confirm to start/stop. Inaction on red is NOT proof of inhibition — signal quality and false/missed triggers are recorded. BCI uses GamepadLite.")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
