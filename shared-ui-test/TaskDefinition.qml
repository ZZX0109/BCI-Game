import QtQml

QtObject {
    readonly property int apiMajor: 1
    readonly property int gameApi: 1
    readonly property string moduleKind: "games"
    readonly property string moduleId: "shared-ui-test"
    readonly property string version: "0.1.0"
    readonly property string title: qsTr("SharedUI Import Test")
    readonly property string description: qsTr("Verify SharedUI module can be imported from dev root.")
    readonly property string entryPoint: "Main.qml"
    readonly property int effector: 2
    readonly property int designWidth: 1000
    readonly property int designHeight: 700
}
