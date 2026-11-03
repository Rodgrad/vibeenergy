import QtQuick
import QtQuick.Controls
import QtTest
import "../../plasmoid/contents/ui" as UI

TestCase {
    id: testCase
    name: "TurboVisualLifecycle"
    when: windowShown
    width: 420; height: 260
    visible: true
    UI.TurboEffects { id: effects; width: 400; height: 240 }
    UI.TurboButton { id: button; x: 30; y: 50 }
    SignalSpy { id: clicks; target: button; signalName: "clicked" }
    function init() { effects.strength=0; effects.reducedMotion=false; effects.time=0; button.turboActive=false; clicks.clear() }
    function test_normal_mode_has_no_effect_renderer() {
        compare(effects.rendering,false)
        compare(effects.visible,false)
        compare(effects.enabled,false)
    }
    function test_effects_release_renderer_after_fade() {
        effects.strength=1
        tryCompare(effects,"rendering",true)
        effects.strength=.3
        compare(effects.rendering,true)
        effects.strength=0
        tryCompare(effects,"rendering",false)
        compare(effects.visible,false)
    }
    function test_repeated_activation_has_one_renderer() {
        for(let i=0;i<4;i++) {
            effects.strength=1
            compare(effects.rendering,true)
            effects.strength=0
            compare(effects.rendering,false)
        }
    }
    function test_reduced_motion_is_static() {
        effects.reducedMotion=true
        effects.strength=1
        compare(effects.rendering,true)
        compare(effects.animating,false)
        effects.strength=0
        compare(effects.rendering,false)
    }
    function test_effects_do_not_intercept_button_input_or_change_geometry() {
        const oldWidth=button.width, oldHeight=button.height
        effects.strength=1
        mouseClick(button,button.width/2,button.height/2)
        compare(clicks.count,1)
        button.turboActive=true
        compare(button.width,oldWidth)
        compare(button.height,oldHeight)
        button.turboActive=false
        compare(button.width,oldWidth)
        compare(button.height,oldHeight)
    }
}
