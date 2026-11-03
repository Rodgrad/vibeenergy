pragma ComponentBehavior: Bound
import QtQuick
Item {
    id: effect
    objectName: backgroundLayer ? "turboBackgroundEffects" : "turboEffects"
    signal lightningHit()
    property real strength: 0
    property real time: 0
    property bool reducedMotion: false
    property bool continuous: false
    property bool borderOnly: false
    property bool backgroundLayer: false
    property rect frame: Qt.rect(0,0,width,height)
    property point origin: Qt.point(width*.85,height*.5)
    readonly property bool gpuAvailable: GraphicsInfo.api!==GraphicsInfo.Unknown && GraphicsInfo.api!==GraphicsInfo.Software && GraphicsInfo.api!==GraphicsInfo.Null
    readonly property bool ready: loader.status===Loader.Ready
    readonly property bool rendering: loader.active
    readonly property bool animating: rendering && !reducedMotion
    enabled: false
    clip: true
    visible: strength > .001
    Loader {
        id: loader
        objectName: "turboEffectLoader"
        anchors.fill: parent
        active: effect.strength > .001
        source: "TurboSoftLayer.qml"
        onLoaded: item.effect=effect
    }
}
