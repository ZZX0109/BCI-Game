import QtQuick
import QtQuick3D

View3D {
    id: view
    property var gameRoot: null
    camera: orbitCamera
    function projectVoxel(p) {
        var syncCameraPosition = orbitCamera.position
        return mapFrom3DScene(Qt.vector3d(p[0] * gameRoot.voxelUnit, p[1] * gameRoot.voxelUnit, p[2] * gameRoot.voxelUnit))
    }
    function pickPiece(x, y) {
        var hit = pick(x,y)
        return hit.objectHit ? hit.objectHit.objectName : ""
    }
    environment: SceneEnvironment {
        clearColor: "#050505"
        backgroundMode: SceneEnvironment.Transparent
        antialiasingMode: SceneEnvironment.MSAA
        antialiasingQuality: SceneEnvironment.High
        tonemapMode: SceneEnvironment.TonemapModeAces
    }
    PerspectiveCamera {
        id: orbitCamera
        fieldOfView: 40
        clipNear: 5; clipFar: 2500
        readonly property real yaw: view.gameRoot ? view.gameRoot.camYaw : 34
        readonly property real pitch: view.gameRoot ? view.gameRoot.camPitch : 26
        readonly property real dist: view.gameRoot ? view.gameRoot.camDist : 350
        readonly property var center: view.gameRoot ? view.gameRoot.cameraCenter : [0,0,0]
        position: Qt.vector3d(center[0]*21 + dist * Math.cos(pitch * Math.PI / 180) * Math.sin(yaw * Math.PI / 180), center[1]*21 + dist * Math.sin(pitch * Math.PI / 180), center[2]*21 + dist * Math.cos(pitch * Math.PI / 180) * Math.cos(yaw * Math.PI / 180))
        eulerRotation: Qt.vector3d(-pitch,yaw,0)
    }
    DirectionalLight { eulerRotation: Qt.vector3d(-40,-35,0); brightness: 1.25; castsShadow: true; shadowFactor: 40; shadowMapQuality: Light.ShadowMapQualityHigh }
    DirectionalLight { eulerRotation: Qt.vector3d(-18,140,0); brightness: 0.55 }
    DirectionalLight { eulerRotation: Qt.vector3d(50,30,0); brightness: 0.3 }
    // Open-space presentation: no rectangular floor or backdrop edge.
    Repeater3D {
        model: view.gameRoot ? view.gameRoot.level.pieces : []
        delegate: Node {
            id: pieceNode
            required property var modelData
            readonly property string pid: modelData.id
            readonly property var root: view.gameRoot
            readonly property var off: root ? root.offsetOf(pid) : [0,0,0]
            readonly property bool selected: root && root.selectedId === pid
            readonly property bool blocked: root && root.blockerId === pid
            readonly property bool hovered: root && root.hoverId === pid
            opacity: !root || root.inspectPiece || selected || hovered || blocked ? 1 : 0.63
            visible: root && root.removedMap[pid] !== true && (!root.inspectPiece || root.selectedId === pid)
            position: Qt.vector3d(off[0]*21,off[1]*21,off[2]*21)
            Repeater3D {
                model: pieceNode.modelData.boxes
                delegate: Model {
                    required property var modelData
                    objectName: pieceNode.pid
                    source: "#Cube"
                    pickable: pieceNode.visible
                    position: Qt.vector3d(modelData.c[0]*21,modelData.c[1]*21,modelData.c[2]*21)
                    scale: Qt.vector3d(modelData.s[0]*21/100,modelData.s[1]*21/100,modelData.s[2]*21/100)
                    castsShadows: true
                    receivesShadows: true
                    materials: PrincipledMaterial {
                        baseColor: pieceNode.root ? pieceNode.root.pieceColor(pieceNode.pid) : "#D5AE7B"
                        baseColorMap: Texture { source: "assets/wood.png"; scaleU: 3; scaleV: 1; rotationUV: pieceNode.modelData.axis === "y" ? 0 : 90 }
                        roughness: 0.76
                        metalness: 0
                        emissiveFactor: pieceNode.blocked ? Qt.vector3d(0.28,0.012,0.006) : pieceNode.hovered ? Qt.vector3d(0.16,0.10,0.02) : pieceNode.selected ? Qt.vector3d(0.075,0.06,0.025) : Qt.vector3d(0,0,0)
                    }
                }
            }
        }
    }
    // Thin red patches are the actual axis contact faces, derived from the
    // same AABBs as collision; they do not add collision or reveal a next move.
    Repeater3D {
        model: view.gameRoot ? view.gameRoot.contactMarkers : []
        delegate: Model {
            required property var modelData
            source: "#Cube"
            position: Qt.vector3d(modelData.c[0]*21,modelData.c[1]*21,modelData.c[2]*21)
            scale: Qt.vector3d(modelData.s[0]*21/100,modelData.s[1]*21/100,modelData.s[2]*21/100)
            materials: PrincipledMaterial { baseColor: "#E55E48"; emissiveFactor: Qt.vector3d(.5,.03,.01); roughness: .8; cullMode: Material.NoCulling }
        }
    }
}
