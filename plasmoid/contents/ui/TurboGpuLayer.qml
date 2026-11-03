import QtQuick
import "EnergyLocal" 1.0
PlasmaField {
    property var effect
    onLightningHit: if(effect)effect.lightningHit()
    time: effect && !effect.reducedMotion ? effect.time : 0
    intensity: effect ? effect.strength : 0
    frame: effect ? effect.frame : Qt.rect(0,0,width,height)
    origin: effect ? effect.origin : Qt.point(width*.85,height*.5)
    borderOnly: effect ? effect.borderOnly : false
    backgroundLayer: effect ? effect.backgroundLayer : false
    continuous: effect ? effect.continuous : false
    reducedMotion: effect ? effect.reducedMotion : false
}
