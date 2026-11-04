pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Templates as T
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import "EnergyLocal" 1.0
import "GpuSetup.js" as GpuSetup
import "History.js" as History

PlasmoidItem {
    id: root
    EnergyBridge { id: bridge }
    property var snapshot: bridge.state
    property var devices: snapshot.devices || []
    readonly property bool nvidiaSmiMissing: GpuSetup.needsNvidiaSmi(devices)
    property var daily: snapshot.daily || []
    property string currency: snapshot.config ? snapshot.config.currency : "EUR"
    readonly property var currencyCodes: ["EUR","USD","GBP","CHF","CAD","AUD","NZD","JPY","CNY","INR","KRW","BRL","MXN","PLN","CZK","DKK","NOK","SEK","HUF","RON","RSD","BAM","MKD","ALL","TRY","UAH","ISK","GEL","SGD","HKD","TWD","THB","MYR","IDR","PHP","VND","ZAR","AED","SAR","QAR","KWD","ILS","EGP","NGN","KES","ARS","CLP","COP","PEN","PKR","BDT","LKR"]
    property real age: 999999
    property bool fresh: snapshot.running === true && age < Math.max(30, (snapshot.config ? snapshot.config.interval : 10) * 3)
    property string calendarToday: bridge.today()
    property string thirtyDaysStart: bridge.daysAgo(29)
    property string startDate: root.thirtyDaysStart
    property string endDate: root.calendarToday
    function validDate(text) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return false
        const d = new Date(text + "T12:00:00")
        return !isNaN(d.getTime()) && d.getFullYear() === Number(text.slice(0,4)) && d.getMonth()+1 === Number(text.slice(5,7)) && d.getDate() === Number(text.slice(8,10))
    }
    property string historyCurrency: ""
    readonly property var historyCurrencies: [...new Set([root.currency].concat(snapshot.currencies || [], snapshot.config ? snapshot.config.history_currencies || [] : [], daily.map(r => r.currency || root.currency)))].sort()
    property var rangeRows: daily.filter(r => r.day >= startDate && r.day <= endDate && (!historyCurrency || (r.currency || root.currency) === historyCurrency))
    readonly property string measurementScopeText: root.cpuUnavailable ? i18n("CPU monitoring unavailable. GPU readings exclude other system components (motherboard, storage, fans, etc.).") : i18n("CPU and GPU components only. Other hardware and PSU losses are excluded; use a wall meter for whole-PC consumption.")
    property bool cpuUnavailable: !fresh || !devices.some(d => d.kind === "cpu" && d.account !== false && typeof d.watts === "number" && Number.isFinite(d.watts) && d.watts >= 0 && d.quality !== "unavailable")
    property real selectedKwh: sum(rangeRows, "kwh")
    function sum(rows, field) { return rows.reduce((a,r) => a + Number(r[field] || 0), 0) }
    function watts(kind) {
        const list = devices.filter(d => d.kind === kind && d.account !== false && d.watts !== null && d.watts !== undefined)
        return fresh && list.length ? sum(list, "watts").toFixed(1) + " W" : "—"
    }
    function knownWatts() {
        const list = devices.filter(d => d.account !== false && d.watts !== null && d.watts !== undefined)
        return fresh && list.length ? sum(list, "watts").toFixed(1) + " W" : "—"
    }
    function money(rows) {
        return History.money(rows, root.currency)
    }
    function energyValue(rows) { const kwh=sum(rows,"kwh"); return rows.length ? (kwh < 1 ? (kwh*1000).toFixed(1) : kwh.toFixed(2)) : "—" }
    function energyUnit(rows) { return sum(rows,"kwh") < 1 ? "Wh" : "kWh" }
    function sourceStatus(kind) {
        const list=devices.filter(d => d.kind===kind && d.account!==false)
        if (!fresh) return i18n("Waiting for live readings")
        const valid=list.filter(d => d.watts!==null && d.watts!==undefined)
        if (!valid.length) return list.some(d => (d.error || "").indexOf("permission denied")>=0) ? i18n("Sensor access restricted") : i18n("No readable power sensor")
        if (valid.some(d => d.energy_eligible === false)) return i18n("From log · live watts only")
        return valid.some(d => d.quality==="imported from log") ? i18n("From your CPU log") : valid.some(d => d.quality==="estimated") ? i18n("Estimated · demo data") : i18n("Measured · %1 device(s)",valid.length)
    }
    function energy(rows) { return rows.length ? sum(rows, "kwh").toFixed(4) + " kWh" : i18n("Unknown / no recorded energy") }
    function refreshAge() { age = snapshot.timestamp ? Date.now()/1000 - snapshot.timestamp : 999999; calendarToday=bridge.today(); thirtyDaysStart=bridge.daysAgo(29) }
    property var livePoints: []
    function liveWatts(kind) {
        const list=devices.filter(d => d.kind===kind && d.account!==false && typeof d.watts==="number" && Number.isFinite(d.watts))
        return fresh && list.length ? sum(list,"watts") : null
    }
    function captureLivePoint() {
        const stamp=Number(snapshot.timestamp || 0)
        if(!fresh || !stamp || (livePoints.length && livePoints[livePoints.length-1].timestamp>=stamp))return
        const current=snapshot.devices || []
        function value(kind) {
            const rows=current.filter(d=>d.kind===kind && d.account!==false && typeof d.watts==="number" && Number.isFinite(d.watts))
            return rows.length ? sum(rows,"watts") : null
        }
        livePoints=livePoints.filter(p=>p.timestamp>=stamp-3600).concat([{timestamp:stamp,cpu:value("cpu"),gpu:value("gpu")}])
    }
    property var historyGeneration: null
    onSnapshotChanged: {
        if(snapshot.history_generation !== undefined && snapshot.history_generation !== historyGeneration) {
            livePoints=[];historyGeneration=snapshot.history_generation
        }
        refreshAge(); captureLivePoint()
    }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.refreshAge() }
    Component.onCompleted: bridge.service("start")
    toolTipMainText: i18n("vibeenergy — CPU/GPU components")
    toolTipSubText: fresh ? i18n("Measured components only; partial coverage possible") : i18n("Collector stopped or readings stale")
    compactRepresentation: Item {
        implicitWidth: 380
        implicitHeight: compactLabel.implicitHeight
        Controls.Label { color: "#f0f3f6";
            id: compactLabel; anchors.centerIn: parent; width: parent.width; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
            text: parent.width < 90 ? (root.fresh ? "⚡" : "⚠") :
                "CPU " + root.watts("cpu") + " · GPU " + root.watts("gpu") +
                (parent.width > 220 ? " · ∑ " + root.knownWatts() : "") +
                (parent.width > 340 ? " · " + root.money(root.daily.filter(r => r.day === root.calendarToday)) : "")
            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
        }
        MouseArea { anchors.fill: parent; onClicked: root.expanded = !root.expanded }
    }
    fullRepresentation: Item {
        id: viewport
        property int edgeMargin: 0
        property bool frameless: false
        property alias turboActive: dashboard.turboActive
        property alias turboStrength: dashboard.turboStrength
        property alias turboTime: dashboard.turboTime
        property alias reducedMotion: dashboard.reducedMotion
        implicitWidth: 1280+edgeMargin*2; implicitHeight: 920+edgeMargin*2
        Layout.minimumWidth: 360+edgeMargin*2; Layout.minimumHeight: 420+edgeMargin*2
        function toggleTurbo() { dashboard.toggleTurbo() }
        function prepareSurface() {
            frameless=bridge.prepareAppWindow(viewport)
            bridge.prepareTurboSurface(viewport)
            Qt.callLater(function(){ bridge.initializeWindowSize(viewport,Math.ceil(viewport.implicitWidth),Math.ceil(Math.max(viewport.implicitHeight,172+sidebarContents.implicitHeight+edgeMargin*2))) })
        }
        Component.onCompleted: Qt.callLater(prepareSurface)
        onWindowChanged: Qt.callLater(prepareSurface)
        Timer {
            interval: 100
            running: bridge.launchedWithSplash && viewport.visible && viewport.Window.window !== null && viewport.Window.window.visible
            onTriggered: bridge.dashboardReady()
        }
        Connections {
            target: viewport.Window.window
            function onVisibilityChanged() {
                if(viewport.Window.window.visibility===Window.Hidden || viewport.Window.window.visibility===Window.Minimized)dashboard.pauseTurbo()
                else if(dashboard.alwaysOn)dashboard.startTurbo()
            }
        }
        Rectangle {
        id: dashboard
        anchors.fill: parent; anchors.margins: viewport.edgeMargin
        objectName: "dashboard"
        property bool turboActive: false
        property bool audioTail: false
        property bool alwaysOn: bridge.turboAlwaysOn
        property bool turboReady: false
        property bool splashReminderShown: false
        property int turboDuration: 5000
        property bool pendingTurbo: false
        property var preparedTurboComponents: []
        Timer {
            interval: 250; running: bridge.startupComplete
            onTriggered: {
                // Compile in the background without creating an idle effect renderer.
                dashboard.preparedTurboComponents=[
                    Qt.createComponent(Qt.resolvedUrl("TurboGpuLayer.qml"),Component.Asynchronous),
                    Qt.createComponent(Qt.resolvedUrl("TurboSoftLayer.qml"),Component.Asynchronous),
                    Qt.createComponent(Qt.resolvedUrl("TurboAudio.qml"),Component.Asynchronous)
                ]
            }
        }
        Connections {
            target: bridge
            function onTurboSoundEnabledChanged() {
                if(!bridge.turboSoundEnabled) dashboard.audioTail=false
            }
            function onStartupCompleteChanged() {
                if(bridge.startupComplete && (dashboard.alwaysOn || dashboard.pendingTurbo)) {
                    dashboard.pendingTurbo=false
                    dashboard.startTurbo()
                }
            }
        }
        onAlwaysOnChanged: if(turboReady) { if(alwaysOn)startTurbo(); else {turboClock.stop();continuousTurboClock.stop();stopTurbo()} }
        Timer {
            interval: 600; running: !dashboard.splashReminderShown && bridge.startupComplete && !dashboard.turboActive && viewport.frameless && viewport.visible && bridge.splashEnabled && !bridge.splashSoundPromptDismissed
            onTriggered: {
                dashboard.splashReminderShown=true
                splashSoundReminder.open()
            }
        }
        Controls.Popup {
            id: splashSoundReminder
            objectName: "splashSoundReminder"
            parent: viewport
            anchors.centerIn: parent
            width: Math.min(420, dashboard.width-32)
            padding: 22; modal: false; dim: false; focus: false
            background: Rectangle { color: "#252d37"; radius: 12; border.color: "#3a4653" }
            contentItem: ColumnLayout {
                spacing: 14
                Controls.Label { text: i18n("Turn off splash"); color: "#f0f3f6"; font.bold: true; font.pointSize: 14 }
                Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; text: i18n("Turn off the splash sound or skip the startup splash entirely. You can change either option later in Settings.") }
                Controls.CheckBox {
                    id: hideSplashReminder
                    text: i18n("Don’t show again")
                    palette.text: "#f0f3f6"; palette.windowText: "#f0f3f6"
                }
                Flow {
                    Layout.fillWidth: true; spacing: 8
                    ActionButton { text: i18n("Turn off splash sound"); onClicked: { bridge.splashSoundEnabled=false; splashSoundReminder.close() } }
                    ActionButton { text: i18n("Turn off splash"); onClicked: { bridge.splashEnabled=false; splashSoundReminder.close() } }
                    ActionButton { text: i18n("Done"); onClicked: splashSoundReminder.close() }
                }
            }
            onClosed: { if(hideSplashReminder.checked) bridge.splashSoundPromptDismissed=true }
        }
        Component.onCompleted: { turboReady=true; if(alwaysOn)Qt.callLater(startTurbo) }
        property bool reducedMotion: bridge.reducedMotion || Kirigami.Units.longDuration<=1
        property real turboStrength: turboActive ? 1 : 0
        property real turboTime: 0
        property real turboProgress: turboActive ? (alwaysOn || reducedMotion ? 1 : Math.max(0,1-turboTime/(turboDuration/1000))) : 0
        property bool wide: width >= 1000
        property point turboOrigin: {
            const layoutWidth=width, layoutHeight=height
            const sidebarScrollY=sidebarScroll.contentItem ? sidebarScroll.contentItem.contentY : 0
            return wide ? sidebarTurbo.mapToItem(viewport,sidebarTurbo.width/2,sidebarTurbo.height/2) : headerTurbo.mapToItem(viewport,headerTurbo.width/2,headerTurbo.height/2)
        }
        Behavior on turboStrength { NumberAnimation { duration: dashboard.reducedMotion ? 100 : dashboard.turboActive ? 180 : 750; easing.type: Easing.InOutCubic } }
        onTurboStrengthChanged: if(turboStrength<=.001 && !turboActive){turboClock.stop();continuousTurboClock.stop()}
        function stopTurbo(playSound=true,publish=true) {
            turboFinish.stop()
            // Publish the transition before audio or renderer work can delay it.
            if(publish)bridge.publishTurbo(false)
            const playTail=turboActive && playSound && bridge.turboSoundEnabled && turboAudio.item
            audioTail=!!playTail
            turboActive=false
            if(playTail && turboAudio.item)turboAudio.item.playPowerOff()
        }
        function pauseTurbo() { turboClock.stop();continuousTurboClock.stop();stopTurbo(false,false) }
        function startTurbo(duration=5000) {
            if(!bridge.startupComplete) { pendingTurbo=true; return }
            // Set the shared burst deadline before activating the audio Loader.
            turboDuration=duration
            if(!alwaysOn)bridge.publishTurbo(true,duration)
            const existingAudio=turboAudio.item
            turboClock.stop();continuousTurboClock.stop();turboFinish.stop();turboTime=0;turboActive=true
            if(!reducedMotion){if(alwaysOn)continuousTurboClock.restart();else turboClock.restart()}
            if(!alwaysOn)turboFinish.restart()
            if(existingAudio)Qt.callLater(function(){if(dashboard.turboActive && turboAudio.item)turboAudio.item.resumeBoost()})
        }
        function toggleTurbo() {
            if(pendingTurbo) { pendingTurbo=false; if(alwaysOn)bridge.turboAlwaysOn=false; return }
            if(alwaysOn) { bridge.turboAlwaysOn=false;stopTurbo();return }
            if(turboActive) { stopTurbo();return }
            startTurbo()
        }
        NumberAnimation { id: turboClock; target: dashboard; property: "turboTime"; from: 0; to: 6; duration: 6000 }
        NumberAnimation { id: continuousTurboClock; target: dashboard; property: "turboTime"; from: 0; to: 86400; duration: 86400000; loops: Animation.Infinite }
        Timer { id: turboFinish; interval: dashboard.turboDuration; onTriggered: if(!dashboard.alwaysOn)dashboard.stopTurbo() }
        Kirigami.Theme.inherit: false
        Kirigami.Theme.backgroundColor: "#171c23"
        Kirigami.Theme.textColor: "#f0f3f6"
        Kirigami.Theme.disabledTextColor: "#a7b3bf"
        Kirigami.Theme.highlightColor: "#2788c7"
        Kirigami.Theme.highlightedTextColor: "#f0f3f6"
        Kirigami.Theme.positiveTextColor: "#35c76a"
        Kirigami.Theme.neutralTextColor: "#d6ae68"
        Loader {
            id: turboAudio
            active: bridge.turboSoundEnabled && (dashboard.turboActive || dashboard.audioTail) && !dashboard.reducedMotion
            asynchronous: true
            onLoaded: if(dashboard.turboActive) item.resumeBoost()
            source: "TurboAudio.qml"
        }
        Timer {
            interval: 2500; running: dashboard.audioTail
            onTriggered: dashboard.audioTail=false
        }
        Connections {
            target: turboAudio.item
            function onFinishingChanged() { if(turboAudio.item && !turboAudio.item.finishing) dashboard.audioTail=false }
        }
        Binding {
            target: turboAudio.item
            property: "level"
            value: bridge.turboSoundVolume
        }
        CpuSetupPopup { id: cpuSetupPopup; backend: bridge }
        NvidiaSetupPopup { id: nvidiaSetupPopup; backend: bridge }
        CurrencyChangePopup {
            id: currencyChangePopup
            backend: bridge
            previousCurrency: root.currency
            existingCurrencies: root.historyCurrencies
        }
        ClearLogsPopup { id: clearLogsPopup; backend: bridge }
        UninstallPopup { id: uninstallPopup; backend: bridge; onCloseAppRequested: bridge.windowAction(dashboard,"quit") }
        color: turboStrength>0 ? Qt.tint("#171c23",Qt.rgba(0,.12,.2,turboStrength*.65)) : "#171c23"
        radius: viewport.edgeMargin>0 ? 14 : 0
        TurboEffects {
            anchors.fill: parent
            backgroundLayer: true
            continuous: dashboard.alwaysOn; strength: dashboard.turboStrength; time: dashboard.turboTime; reducedMotion: dashboard.reducedMotion
            origin: Qt.point(dashboard.turboOrigin.x-viewport.edgeMargin,dashboard.turboOrigin.y-viewport.edgeMargin)
        }
        MouseArea {
            visible: viewport.frameless
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.rightMargin: 120; height: dashboard.width<720 ? 30 : 100
            acceptedButtons: Qt.LeftButton
            onPressed: mouse => bridge.moveAppWindow(viewport)
            onDoubleClicked: mouse => bridge.windowAction(viewport,"maximize")
        }
        RowLayout {
            id: windowControls
            objectName: "windowControls"
            visible: viewport.frameless
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.top: parent.top; anchors.topMargin: dashboard.width<720 ? 4 : 20
            spacing: 4; z: 20
            Repeater {
                model: [["—",i18n("Minimize window"),"minimize"],["□",i18n("Maximize or restore window"),"maximize"],["×",i18n("Close window"),"close"]]
                delegate: Controls.ToolButton {
                    required property var modelData
                    implicitWidth: 30; implicitHeight: 30
                    text: modelData[0]; Accessible.name: modelData[1]
                    hoverEnabled: true
                    background: Rectangle { radius: 6; color: parent.hovered ? (parent.modelData[2]==="close" ? "#a43b48" : "#354451") : "transparent" }
                    contentItem: Controls.Label { text: parent.text; color: "#d6dfe8"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pointSize: 16 }
                    onClicked: bridge.windowAction(viewport,modelData[2])
                    Controls.ToolTip.visible: hovered
                    Controls.ToolTip.text: modelData[1]
                }
            }
        }
        Repeater {
            model: viewport.frameless ? [Qt.LeftEdge,Qt.RightEdge,Qt.TopEdge,Qt.BottomEdge,Qt.TopEdge|Qt.LeftEdge,Qt.TopEdge|Qt.RightEdge,Qt.BottomEdge|Qt.LeftEdge,Qt.BottomEdge|Qt.RightEdge] : []
            delegate: MouseArea {
                required property int modelData
                readonly property bool edgeLeft: (modelData&Qt.LeftEdge)!==0
                readonly property bool edgeRight: (modelData&Qt.RightEdge)!==0
                readonly property bool edgeTop: (modelData&Qt.TopEdge)!==0
                readonly property bool edgeBottom: (modelData&Qt.BottomEdge)!==0
                readonly property bool corner: (edgeLeft||edgeRight)&&(edgeTop||edgeBottom)
                width: corner?14:(edgeLeft||edgeRight?6:dashboard.width-28)
                height: corner?14:(edgeTop||edgeBottom?6:dashboard.height-28)
                x: edgeLeft?0:edgeRight?dashboard.width-width:14
                y: edgeTop?0:edgeBottom?dashboard.height-height:14
                z: 30
                enabled: viewport.Window.window && viewport.Window.window.visibility!==Window.Maximized && viewport.Window.window.visibility!==Window.FullScreen
                cursorShape: corner ? ((edgeLeft&&edgeTop)||(edgeRight&&edgeBottom)?Qt.SizeFDiagCursor:Qt.SizeBDiagCursor) : (edgeLeft||edgeRight?Qt.SizeHorCursor:Qt.SizeVerCursor)
                acceptedButtons: Qt.LeftButton
                onPressed: mouse => bridge.resizeAppWindow(viewport,modelData)
            }
        }
        RowLayout {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.leftMargin: dashboard.width < 480 ? 14 : 24; anchors.rightMargin: viewport.frameless && dashboard.width>=720 ? 128 : (dashboard.width < 480 ? 14 : 24)
            anchors.topMargin: viewport.frameless && dashboard.width<720 ? 38 : 20; height: 72
            spacing: 16
                Rectangle {
                    Layout.preferredWidth: dashboard.width < 600 ? 40 : 60; Layout.preferredHeight: dashboard.width < 600 ? 40 : 60; radius: 14
                    color: Qt.tint("#1d4d48",Qt.rgba(0,.4,.7,dashboard.turboStrength*.55))
                    border.width: 1; border.color: Qt.rgba(0,.85,1,dashboard.turboStrength)
                    Rectangle { anchors.fill: parent; anchors.margins: -3; radius: 17; color: "transparent"; border.width: 3; border.color: Qt.rgba(0,.85,1,dashboard.turboStrength*.15) }
                    Image { anchors.centerIn: parent; width: 38; height: 38; source: "../icons/bolt.svg" }
                }
                ColumnLayout {
                    spacing: 2; Layout.fillWidth: true
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; elide: Text.ElideRight; text: "VibeEnergy"; font.pointSize: dashboard.width < 600 ? 18 : 28; font.weight: Font.DemiBold }
                    Controls.Label { color: "#f0f3f6"; text: i18n("Energy monitor for Linux"); font.pointSize: dashboard.width < 600 ? 10 : 13; opacity: .75; Layout.fillWidth: true; elide: Text.ElideRight }
                }
                TurboButton { id: headerTurbo; glow: dashboard.turboStrength; visible: !dashboard.wide; compact: true; turboActive: dashboard.turboActive; onClicked: dashboard.toggleTurbo() }
                RowLayout {
                    spacing: 6
                    Rectangle { width: 7; height: 7; radius: 4; color: root.fresh ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor }
                    Controls.Label { color: "#f0f3f6"; visible: dashboard.width >= 600; text: bridge.demo ? i18n("Demo") : root.fresh ? i18n("Recording") : i18n("Offline"); font.pointSize: 10 }
                }
                            Rectangle { visible: dashboard.wide; Layout.leftMargin: 16; Layout.rightMargin: 12; width: 1; height: 30; color: "#3a4653" }
                Controls.Label { visible: dashboard.wide; text: i18n("Last sample: %1 s ago", Math.max(0,Math.floor(root.age))); color: "#d6dfe8"; font.pointSize: 12 }
            }
        ColumnLayout {
            anchors.fill: parent; anchors.margins: dashboard.width < 480 ? 14 : 24
            anchors.topMargin: viewport.frameless && dashboard.width<720 ? 134 : 116
            anchors.rightMargin: dashboard.wide ? 336 : (dashboard.width < 480 ? 14 : 24)
            spacing: 18

            Controls.TabBar {
                id: tabs; objectName: "dashboardTabs"; visible: !dashboard.wide; Layout.fillWidth: true; spacing: 4
                background: Rectangle { radius: 12; color: Qt.tint("#202730",Qt.rgba(0,.12,.2,dashboard.turboStrength*.6)); border.width: 1; border.color: Qt.rgba(0,.85,1,dashboard.turboStrength*.4) }
                Repeater {
                    model: [i18n("Overview"),i18n("History"),i18n("Sensors"),i18n("Settings")]
                    delegate: Controls.TabButton {
                        required property string modelData
                        required property int index
                        text: modelData; implicitHeight: 46
                        font.pointSize: 10; font.weight: checked ? Font.DemiBold : Font.Normal
                        background: Rectangle { radius: 9; color: parent.checked ? "#24465e" : parent.hovered ? Qt.rgba(Kirigami.Theme.textColor.r,Kirigami.Theme.textColor.g,Kirigami.Theme.textColor.b,.04) : "transparent"; border.width: parent.activeFocus ? 2 : parent.checked ? 1 : 0; border.color: parent.activeFocus ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r,Kirigami.Theme.textColor.g,Kirigami.Theme.textColor.b,.1) }
                        contentItem: Item {
                            implicitWidth: tabContent.implicitWidth
                            implicitHeight: tabContent.implicitHeight
                            RowLayout {
                                id: tabContent
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth,parent.width)
                                spacing: dashboard.width>=600 ? 10 : 0
                                AppIcon { visible: dashboard.width>=600; kind: ["home","history","cpu","settings"][index]; ink: tabs.currentIndex===index ? "#16c4eb" : "#b2c8dd"; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                                Controls.Label { text: modelData; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; color: "#f0f3f6"; font.pointSize: dashboard.width>=1000 ? 13 : 10; font.weight: tabs.currentIndex===index ? Font.DemiBold : Font.Normal }
                            }
                        }
                    }
                }
            }
            StackLayout {
                currentIndex: tabs.currentIndex; Layout.fillWidth: true; Layout.fillHeight: true
                Controls.ScrollView {
                    id: overviewScroll
                    contentWidth: availableWidth
                    Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
                    ColumnLayout {
                        width: overviewScroll.availableWidth; spacing: 16
                        GridLayout {
                            Layout.fillWidth: true; columns: width >= 620 ? 3 : 1; columnSpacing: 16; rowSpacing: 12
                            PowerCard { Layout.fillWidth: true; energy: dashboard.turboStrength; title: "CPU"; iconKind: "cpu"; trend: root.livePoints; accent: "#43b8d4"; value: root.watts("cpu"); detail: root.cpuUnavailable ? i18n("Sensor unavailable") : root.sourceStatus("cpu"); available: !root.cpuUnavailable; activation: root.cpuUnavailable; onActivateRequested: cpuSetupPopup.open() }
                            PowerCard { Layout.fillWidth: true; energy: dashboard.turboStrength; id: overviewGpuCard; title: "GPU"; iconKind: "gpu"; activation: root.nvidiaSmiMissing; activationText: i18n("Install nvidia-smi…"); onActivateRequested: nvidiaSetupPopup.open(); trend: root.livePoints; accent: "#35c76a"; value: root.watts("gpu"); detail: root.sourceStatus("gpu"); available: root.liveWatts("gpu")!==null }
                            PowerCard { Layout.fillWidth: true; energy: dashboard.turboStrength; title: i18n("Total (CPU + GPU)"); iconKind: "bolt"; trend: root.livePoints; accent: "#9877cc"; value: root.knownWatts(); detail: i18n("Measured components"); available: root.fresh }
                        }
                        Surface {
                            energy: dashboard.turboStrength
                            Layout.fillWidth: true; implicitHeight: liveGraphContent.implicitHeight+32
                            ColumnLayout {
                                id: liveGraphContent; anchors.fill: parent; anchors.margins: 16; spacing: 12
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 10
                                    AppIcon { kind: "wave"; ink: "#43b8d4"; Layout.preferredWidth: 28; Layout.preferredHeight: 28 }
                                    Controls.Label { text: i18n("Live power consumption"); color: "#f0f3f6"; font.pointSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                                    DarkComboBox {
                                        id: liveRange
                                        implicitWidth: 170; implicitHeight: 36
                                        background: Rectangle { radius: 8; color: "#202831"; border.color: "#3a4653" }
                                        font.pointSize: 11
                                        model: [i18n("Last 5 minutes"),i18n("Last 10 minutes"),i18n("Last 15 minutes"),i18n("Last 60 minutes")]; currentIndex: 3
                                        palette.text: "#f0f3f6"; palette.buttonText: "#f0f3f6"; palette.button: "#252d37"; palette.window: "#252d37"; palette.windowText: "#f0f3f6"
                                    }
                                }
                                LivePowerGraph { Layout.fillWidth: true; energy: dashboard.turboStrength; points: root.livePoints; maxGapSeconds: Math.max(2.5,(root.snapshot.config ? root.snapshot.config.interval : 1)*2.5); rangeSeconds: [300,600,900,3600][liveRange.currentIndex] }
                            }
                        }
                        GridLayout {
                            Layout.fillWidth: true; columns: width >= 780 ? 3 : 1; columnSpacing: 16; rowSpacing: 12
                            Repeater {
                                // Stable delegates: sensor snapshots only update their values.
                                model: 3
                                delegate: OverviewSummaryCard {
                                    required property int index
                                    property var periodRows: index===0 ? root.daily.filter(r=>r.day===root.calendarToday) : index===1 ? root.daily.filter(r=>r.day>=bridge.monthStart() && r.day<=root.calendarToday) : root.daily
                                    symbol: index===2 ? "infinity" : "calendar"
                                    Layout.fillWidth: true; Layout.fillHeight: true; energy: dashboard.turboStrength
                                    title: [i18n("Today"),i18n("This month"),i18n("All time")][index]
                                    energyValue: root.energyValue(periodRows); energyUnit: root.energyUnit(periodRows)
                                    costs: History.costTotals(periodRows.filter(r => (r.currency || root.currency) === root.currency),root.currency); currency: root.currency
                                    emphasized: index===0
                                    accent: ["#a4ffca","#43cbe8","#b79be8"][index]
                                    statusText: index===0 && root.fresh ? i18n("Recording") : periodRows.length ? i18n("Recorded") : i18n("No recorded data")
                                    statusColor: index===0 && root.fresh ? "#35c76a" : "#a7b3bf"
                                }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: overviewNote.implicitHeight+24; radius: 10; color: "#242e37"; border.color: "#3a4653"
                            RowLayout {
                                id: overviewNote; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: 12; spacing: 10
                                AppIcon { kind: "bolt"; ink: "#43b8d4"; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                                Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#d6dfe8"; font.pointSize: 10; text: root.measurementScopeText }
                            }
                        }
                        Item { implicitHeight: 4 }
                    }
                }
            Controls.ScrollView {
                id: historyScroll
                contentWidth: availableWidth
                ColumnLayout {
                    width: historyScroll.availableWidth; spacing: 16
                    Controls.Label { color: "#f0f3f6"; text: i18n("Explore your history"); font.pointSize: 18; font.weight: Font.DemiBold }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 12
                        DarkComboBox {
                            implicitContentWidthPolicy: Controls.ComboBox.WidestText
                            Accessible.name: i18n("History period")
                            currentIndex: 2
                            model: [i18n("Today"), i18n("Last 7 days"), i18n("Last 30 days"), i18n("This month"), i18n("This year"), i18n("All time")]
                            onActivated: {
                                root.endDate=root.calendarToday
                                root.startDate=[root.calendarToday,bridge.daysAgo(6),root.thirtyDaysStart,bridge.monthStart(),root.calendarToday.slice(0,4)+"-01-01",root.daily.length ? root.daily[0].day : root.calendarToday][currentIndex]
                            }
                        }
                        DarkComboBox {
                            objectName: "historyCurrencyFilter"
                            implicitContentWidthPolicy: Controls.ComboBox.WidestText
                            Accessible.name: i18n("Currency history")
                            model: [i18n("All currencies")].concat(root.historyCurrencies)
                            currentIndex: root.historyCurrency ? root.historyCurrencies.indexOf(root.historyCurrency)+1 : 0
                            onActivated: root.historyCurrency = currentIndex > 0 ? root.historyCurrencies[currentIndex-1] : ""
                        }
                        Item { Layout.fillWidth: true }
                    }
                    Controls.Label {
                        Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"
                        text: i18n("Each currency has its own history. All currencies combines energy usage and lists costs separately; no conversion is applied.")
                    }
                    RowLayout {
                        FormField { Layout.fillWidth: true; readOnly: true; text: root.startDate; Accessible.name: i18n("Period start") }
                        FormField { Layout.fillWidth: true; readOnly: true; text: root.endDate; Accessible.name: i18n("Period end") }
                    }
                    Controls.Label { color: "#f0f3f6";
                        Layout.fillWidth: true; wrapMode: Text.Wrap
                        text: i18n("Selected period: %1 to %2", root.startDate, root.endDate)
                        opacity: .7
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: width < 480 ? 1 : 2
                        columnSpacing: 12; rowSpacing: 12
                        MetricCard {
                            Layout.fillWidth: true
                            title: i18n("Combined CPU + GPU energy")
                            value: root.rangeRows.length ? root.selectedKwh.toFixed(4) : "—"
                            unit: "kWh"
                            detail: i18n("Total recorded usage in selected period")
                        }
                        MetricCard {
                            Layout.fillWidth: true
                            title: i18n("Combined CPU + GPU cost")
                            wrapValue: true
                            value: root.money(root.rangeRows).split(" · ").join("\n")
                            detail: i18n("Total recorded cost in selected period")
                        }
                    }
                    Controls.Label { color: "#f0f3f6";
                        Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .65
                        text: i18n("Totals include recorded CPU and GPU usage. Missing readings are excluded.")
                    }
                    EnergyGraph {
                        Layout.fillWidth: true; rows: root.rangeRows
                        startDate: root.startDate; endDate: root.endDate; currency: root.currency
                    }
                    Repeater {
                        model: [...new Set(root.rangeRows.map(r => r.day))].sort().reverse()
                        delegate: Controls.Label { color: "#f0f3f6";
                            required property string modelData
                            Layout.fillWidth: true; wrapMode: Text.Wrap
                            text: modelData+"   "+root.energy(root.rangeRows.filter(r => r.day === modelData))+"   "+root.money(root.rangeRows.filter(r => r.day === modelData))
                        }
                    }
                }
            }
            Controls.ScrollView {
                id: diagnosticsScroll
                contentWidth: availableWidth
                ColumnLayout {
                    width: diagnosticsScroll.availableWidth; spacing: 20
                    Controls.Label { color: "#f0f3f6"; text: i18n("Hardware & sensors"); font.pointSize: 18; font.weight: Font.DemiBold }
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18n("See which devices can be measured and why a reading may be unavailable."); opacity: .7 }
                    Repeater {
                        model: root.devices
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; font.bold: true; text: modelData.name }
                            Controls.Label { color: "#f0f3f6"; text: (modelData.watts !== null ? Number(modelData.watts).toFixed(1)+" W · " : "")+modelData.quality }
                            Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; text: modelData.source }
                            Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData.error || i18n("Sensor readable") }
                            ActionButton { visible: GpuSetup.needsNvidiaSmi([modelData]); primary: true; text: i18n("Install nvidia-smi…"); onClicked: nvidiaSetupPopup.open() }
                            Controls.Label { color: "#f0f3f6"; text: i18n("Last valid: %1", modelData.last_valid ? new Date(modelData.last_valid*1000).toLocaleString() : i18n("Never")) }
                            Controls.Label { color: "#f0f3f6";
                                Layout.fillWidth: true; wrapMode: Text.Wrap
                                property real covered: root.sum(root.daily.filter(r => r.day === root.calendarToday && r.device === modelData.id),"covered_seconds")
                                text: i18n("Today: %1 seconds measured of %2 seconds collector observation", Math.round(covered), Math.round((root.snapshot.observation || {})[root.calendarToday] || 0))
                            }
                        }
                    }
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.snapshot.error || "" }
                }
            }
            Controls.ScrollView {
                id: settingsScroll
                property string autostartState: "unknown"
                property string autostartNotice: ""
                property bool autostartSuccess: false
                property string saveNotice: ""
                property bool saveSuccess: false
                Connections {
                    target: bridge
                    function onServiceFinished(action, success, message) {
                        if(action!=="enable" && action!=="disable")return
                        settingsScroll.autostartState=bridge.autostartState()
                        settingsScroll.autostartSuccess=success
                        settingsScroll.autostartNotice=message
                    }
                    function onSettingsSaveFinished(success, message) {
                        settingsScroll.saveSuccess=success
                        settingsScroll.saveNotice=message
                    }
                }
                function reloadSavedSettings() {
                    autostartState = bridge.autostartState()
                    const saved = bridge.savedSettings()
                    price.text = String(saved.price)
                    curr.currentIndex = curr.model.indexOf(saved.currency)
                    curr.editText = saved.currency
                    interval.resetValue(saved.interval)
                    logPath.text = saved.powerstat_log
                    currencyChangePopup.previousCurrency = saved.currency
                }
                onVisibleChanged: if(visible) Qt.callLater(reloadSavedSettings)
                Component.onCompleted: if(visible) Qt.callLater(reloadSavedSettings)
                contentWidth: availableWidth
                ColumnLayout {
                    width: settingsScroll.availableWidth; spacing: 16
                    Controls.Label { color: "#f0f3f6"; text: i18n("Make it yours"); font.pointSize: 18; font.weight: Font.DemiBold }
                    Surface {
                            energy: dashboard.turboStrength
                        Layout.fillWidth: true; implicitHeight: settingsForm.implicitHeight+36
                        ColumnLayout {
                            id: settingsForm; anchors.fill: parent; anchors.margins: 18; spacing: 10
                            Controls.Label { color: "#f0f3f6"; text: i18n("Electricity & collection"); font.pointSize: 13; font.weight: Font.DemiBold }
                            Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18n("Your electricity price applies to new measurements. Recorded costs keep their original price and currency."); opacity: .65 }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: width >= 480 ? 3 : width >= 320 ? 2 : 1
                                columnSpacing: 12; rowSpacing: 10
                                ColumnLayout {
                                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; spacing: 6
                                    Controls.Label { color: "#f0f3f6"; text: i18n("Price per kWh") }
                                    FormField { id: price; Layout.fillWidth: true; text: String(root.snapshot.config ? root.snapshot.config.price : 0.177); placeholderText: "0.177"; Accessible.name: i18n("Electricity price per kWh") }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; spacing: 6
                                    Controls.Label { color: "#f0f3f6"; text: i18n("Currency") }
                                    DarkComboBox {
                                        id: curr; Layout.fillWidth: true; editable: true
                                        model: root.currencyCodes
                                        currentIndex: model.indexOf(root.currency); editText: root.currency
                                        validator: RegularExpressionValidator { regularExpression: /[A-Za-z]{3}/ }
                                        Accessible.name: i18n("Currency code")
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop; spacing: 6
                                    Controls.Label { color: "#f0f3f6"; text: i18n("Sampling interval (s)") }
                                    DarkSpinBox { id: interval; Layout.fillWidth: true; from: 1; to: 5; editable: true; value: root.snapshot.config ? root.snapshot.config.interval : 1; Accessible.name: i18n("Sampling interval in seconds, from 1 to 5") }
                                }
                            }
                            Controls.Label {
                                Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; font.pointSize: 9
                                text: i18n("Enter the price in the selected currency. Changing currency preserves previous history without conversion.")
                            }
                            Controls.Label {
                                Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; font.pointSize: 9
                                text: i18n("Raw readings: current day only. Daily energy and cost summaries are kept permanently. Cleanup runs while the collector is running, including when it resumes.")
                            }
                            Controls.Label {
                                Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; font.pointSize: 9
                                text: i18n("Estimated daily summaries after 1 year: ~0.36 MiB for two sensors (0.5 KiB per sensor per day). Actual storage varies; raw data is additional.")
                            }
                            Controls.Label { color: "#f0f3f6"; text: i18n("Custom CPU log (optional)"); Layout.topMargin: 6 }
                            FormField { id: logPath; Layout.fillWidth: true; text: root.snapshot.config ? root.snapshot.config.powerstat_log : ""; placeholderText: i18n("Auto-detect logs in ~/.vibeenergy/logs/"); Accessible.name: i18n("Optional Powerstat log path") }
                            ActionButton { text: i18n("Save changes"); primary: true; onClicked: currencyChangePopup.requestSave(price.text,curr.editText,interval.value,logPath.text) }
                            Controls.Label {
                                objectName: "settingsSaveNotice"
                                Layout.fillWidth: true; wrapMode: Text.Wrap
                                visible: settingsScroll.saveNotice.length>0
                                color: settingsScroll.saveSuccess ? "#70dba1" : "#ff9b92"
                                text: (settingsScroll.saveSuccess ? "✓ " : "") + settingsScroll.saveNotice
                            }
                        }
                    }
                    Surface {
                        Layout.fillWidth: true; implicitHeight: appearanceSettings.implicitHeight+36
                        ColumnLayout {
                            id: appearanceSettings; anchors.fill: parent; anchors.margins: 18; spacing: 10
                            Controls.Label { text: i18n("Appearance"); color: "#f0f3f6"; font.pointSize: 13; font.weight: Font.DemiBold }
                            Controls.CheckBox {
                                objectName: "turboAlwaysOnSetting"
                                text: i18n("Turbo Boost always on")
                                palette.windowText: "#f0f3f6"; palette.text: "#f0f3f6"
                                checked: bridge.turboAlwaysOn
                                onClicked: bridge.turboAlwaysOn=checked
                            }
                            Controls.CheckBox {
                                text: i18n("Turbo Boost lightning sounds")
                                palette.windowText: "#f0f3f6"; palette.text: "#f0f3f6"
                                checked: bridge.turboSoundEnabled
                                onClicked: bridge.turboSoundEnabled=checked
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                enabled: bridge.turboSoundEnabled
                                Controls.Label { text: i18n("Sound volume"); color: "#f0f3f6" }
                                Controls.Slider {
                                    Layout.fillWidth: true
                                    from: 0; to: 1; stepSize: .01
                                    value: bridge.turboSoundVolume
                                    Accessible.name: i18n("Turbo Boost sound volume")
                                    onMoved: bridge.turboSoundVolume=value
                                }
                                Controls.Label {
                                    text: Math.round(bridge.turboSoundVolume*100)+"%"
                                    color: "#a7b3bf"
                                    Layout.minimumWidth: 42
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                            Controls.CheckBox {
                                text: i18n("Show startup splash")
                                palette.text: "#f0f3f6"; palette.windowText: "#f0f3f6"
                                checked: bridge.splashEnabled
                                onClicked: bridge.splashEnabled=checked
                            }
                            Controls.CheckBox {
                                enabled: bridge.splashEnabled
                                text: i18n("Splash sound (3% volume)")
                                palette.text: "#f0f3f6"; palette.windowText: "#f0f3f6"
                                checked: bridge.splashSoundEnabled
                                onClicked: bridge.splashSoundEnabled=checked
                            }
                            Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; text: i18n("Keep the visual effects running while this window is visible. Hardware performance and measurement intervals stay unchanged. Reduced-motion preferences are respected.") }
                        }
                    }
                    Surface {
                            energy: dashboard.turboStrength
                        Layout.fillWidth: true; implicitHeight: collectionSettings.implicitHeight+36
                        ColumnLayout {
                            id: collectionSettings; anchors.fill: parent; anchors.margins: 18; spacing: 14
                            Controls.Label { color: "#f0f3f6"; text: i18n("Recording & autostart"); font.pointSize: 13; font.weight: Font.DemiBold }
                            Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18n("Recording starts automatically when you open VibeEnergy and continues in the background. Closing the window keeps the app in the system tray; click its icon to reopen. Use Quit VibeEnergy from the tray to stop recording and exit. Enable autostart to start recording when you log in. Disabling autostart keeps the current recording running."); opacity: .65 }
                            Flow {
                                Layout.fillWidth: true; spacing: 8
                                ActionButton {
                                    objectName: "enableAutostartButton"
                                    text: i18n("Enable autostart"); active: settingsScroll.autostartState==="enabled"
                                    enabled: !bridge.serviceBusy
                                    onClicked: { settingsScroll.autostartNotice=""; bridge.service("enable") }
                                }
                                ActionButton {
                                    objectName: "disableAutostartButton"
                                    text: i18n("Disable autostart"); active: settingsScroll.autostartState==="disabled"
                                    enabled: !bridge.serviceBusy
                                    onClicked: { settingsScroll.autostartNotice=""; bridge.service("disable") }
                                }
                            }
                            Controls.Label {
                                objectName: "autostartStateLabel"
                                Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#43b8ff"
                                text: bridge.serviceBusy ? i18n("Processing…") : settingsScroll.autostartState==="enabled" ? i18n("Autostart enabled") : settingsScroll.autostartState==="disabled" ? i18n("Autostart disabled") : i18n("Could not determine autostart state")
                            }
                            Controls.Label {
                                objectName: "autostartNotice"
                                Layout.fillWidth: true; wrapMode: Text.Wrap
                                visible: settingsScroll.autostartNotice.length>0
                                color: settingsScroll.autostartSuccess ? "#70dba1" : "#ff9b92"
                                text: (settingsScroll.autostartSuccess ? "✓ " : "") + settingsScroll.autostartNotice
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(Kirigami.Theme.textColor.r,Kirigami.Theme.textColor.g,Kirigami.Theme.textColor.b,.1) }
                            Controls.Label { color: "#f0f3f6"; text: i18n("CPU Powerstat recording"); font.weight: Font.DemiBold }
                            Controls.Label { color: "#f0f3f6";
                                Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .7
                                text: i18n("Copy a command and run it in your terminal. Temporary recording needs an open terminal; autostart keeps recording after closing it and after reboot. Stopping preserves logs and history.")
                            }
                            ColumnLayout {
                                id: cpuCommands
                                property string notice: ""
                                Layout.fillWidth: true; spacing: 8
                                function copy(command) { bridge.copyText(command); notice=i18n("Copied. Run the whole command in your terminal.") }
                                CommandCopy { Layout.fillWidth: true; buttonText: i18n("Copy temporary start"); command: bridge.powerstatSetup().foregroundCommand; onCopyRequested: command => cpuCommands.copy(command) }
                                ActionButton {
                                    Layout.fillWidth: true; primary: true
                                    text: bridge.cpuAutostartBusy ? i18n("Waiting for system authorization…") : i18n("Enable CPU autostart…")
                                    enabled: !bridge.cpuAutostartBusy
                                    onClicked: { cpuSetupPopup.open(); cpuSetupPopup.confirmAutostart() }
                                }
                                CommandCopy { Layout.fillWidth: true; buttonText: i18n("Copy vibeenergy Powerstat service runner"); command: bridge.powerstatSetup().serviceRunnerCommand; onCopyRequested: command => cpuCommands.copy(command) }
                                CommandCopy { Layout.fillWidth: true; buttonText: i18n("Copy cron autostart"); command: bridge.powerstatSetup().cronCommand; onCopyRequested: command => cpuCommands.copy(command) }
                                Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: .7; text: i18n("Service runner activates the prepared service. Run the copied cron block once to add boot startup without changing existing jobs or adding duplicates. It starts at the next boot. Use one recording method. The collector handles daily summaries and raw cleanup.") }
                                CommandCopy { Layout.fillWidth: true; buttonText: i18n("Copy stop & disable service autostart"); command: "sudo systemctl disable --now vibeenergy-powerstat.service"; onCopyRequested: command => cpuCommands.copy(command) }
                            }
                            Controls.Label { color: "#f0f3f6";
                                Layout.fillWidth: true; wrapMode: Text.Wrap; visible: cpuCommands.notice.length>0
                                text: cpuCommands.notice
                            }
                        }
                    }
                    Surface {
                        Layout.fillWidth: true
                        implicitHeight: supportSettings.implicitHeight+36
                        ColumnLayout {
                            id: supportSettings
                            anchors.fill: parent; anchors.margins: 18; spacing: 10
                            Controls.Label { text: i18n("Support the project"); color: "#f0f3f6"; font.pointSize: 13; font.weight: Font.DemiBold }
                            Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: i18n("Support VibeEnergy’s development and future projects."); color: "#a7b3bf" }
                            ActionButton {
                                Layout.alignment: Qt.AlignLeft
                                text: qsTr("☕  Power Me with Coffee")
                                font.weight: Font.Bold
                                contentItem: RowLayout {
                                    spacing: 9
                                    Image { source: Qt.resolvedUrl("../icons/coffee.svg"); Layout.preferredWidth: 23; Layout.preferredHeight: 23; fillMode: Image.PreserveAspectFit; Layout.alignment: Qt.AlignVCenter }
                                    Controls.Label { text: qsTr("Power Me with Coffee"); color: "#f0f3f6"; font.weight: Font.Bold; Layout.alignment: Qt.AlignVCenter }
                                }
                                Accessible.name: qsTr("Support VibeEnergy on Ko-fi")
                                background: Rectangle { radius: 8; color: parent.down ? "#bc4010" : parent.hovered ? "#d34d16" : "#e4571d"; border.width: parent.activeFocus ? 2 : 1; border.color: "#ff9b6c" }
                                onClicked: Qt.openUrlExternally("https://ko-fi.com/techtoapes")
                            }
                        }
                    }
                    Surface {
                        Layout.fillWidth: true; implicitHeight: clearLogsSettings.implicitHeight+36
                        ColumnLayout {
                            id: clearLogsSettings
                            anchors.fill: parent; anchors.margins: 18; spacing: 10
                            Controls.Label { text: i18n("Logs & history"); color: "#f0f3f6"; font.pointSize: 13; font.weight: Font.DemiBold }
                            Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; text: i18n("Delete all recorded energy and cost history across every currency, plus raw logs. Your settings are kept.") }
                            ActionButton { text: i18n("Clear all logs & history…"); enabled: !bridge.clearingHistory; onClicked: clearLogsPopup.open() }
                        }
                    }
                    Surface {
                        Layout.fillWidth: true
                        implicitHeight: uninstallSettings.implicitHeight+36
                        ColumnLayout {
                            id: uninstallSettings
                            anchors.fill: parent; anchors.margins: 18; spacing: 12
                            Controls.Label { text: i18n("Remove VibeEnergy"); color: "#f0f3f6"; font.pointSize: 13; font.weight: Font.DemiBold }
                            Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; text: i18n("Remove the background collector and desktop integration. History, settings, and CPU logs are kept. No sudo required.") }
                            ActionButton { text: i18n("Uninstall…"); onClicked: uninstallPopup.open() }
                            CommandCopy {
                                Layout.fillWidth: true; buttonText: i18n("Copy uninstall commands (no sudo)")
                                command: "systemctl --user disable --now energytlk.service &&\nrm -f \"${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/energytlk.service\" \"${XDG_DATA_HOME:-$HOME/.local/share}/applications/vibeenergy.desktop\" &&\nrm -rf -- \"${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/org.energytlk.monitor\" \"${XDG_DATA_HOME:-$HOME/.local/share}/energytlk/app\" &&\nsystemctl --user daemon-reload"
                                onCopyRequested: command => bridge.copyText(command)
                            }
                            Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; text: i18n("Optional: remove the separate system-wide Powerstat service. This requires sudo. CPU recording started in a terminal or crontab must be stopped separately.") }
                            CommandCopy {
                                Layout.fillWidth: true; buttonText: i18n("Copy Powerstat service removal (sudo)")
                                command: "sudo systemctl disable --now vibeenergy-powerstat.service &&\nsudo rm -f /etc/systemd/system/vibeenergy-powerstat.service &&\nsudo systemctl daemon-reload"
                                onCopyRequested: command => bridge.copyText(command)
                            }
                        }
                    }
                    Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; wrapMode: Text.Wrap; text: bridge.message; visible: text.length>0 }
                }
            }
        }
        Controls.Label { color: "#f0f3f6";
            visible: tabs.currentIndex !== 0
            Layout.fillWidth: true; wrapMode: Text.Wrap; font.pointSize: 9; opacity: .65
            text: root.measurementScopeText
        }
        T.ToolButton {
            id: creditsButton
            objectName: "creditsButton"
            implicitWidth: contentItem.implicitWidth + 24
            implicitHeight: contentItem.implicitHeight + 16
            padding: 8
            hoverEnabled: true
            background: Rectangle { radius: 8; color: creditsButton.hovered ? Qt.rgba(Kirigami.Theme.highlightColor.r,Kirigami.Theme.highlightColor.g,Kirigami.Theme.highlightColor.b,.08) : "transparent"; border.width: creditsButton.activeFocus ? 1 : 0; border.color: Kirigami.Theme.highlightColor }
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: parent.width
            text: i18n("About VibeEnergy")
            font.pointSize: 9
            Accessible.name: i18n("About VibeEnergy")
            contentItem: Controls.Label {
                text: creditsButton.text; font: creditsButton.font
                color: creditsButton.hovered ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                opacity: creditsButton.hovered ? 1 : .65
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            }
            onClicked: creditsPopup.open()
            Controls.Popup {
                id: creditsPopup
                objectName: "creditsPopup"
                parent: creditsButton
                width: Math.min(320, root.width > 0 ? root.width - 28 : 320)
                x: (creditsButton.width - width) / 2
                y: -height - 10
                padding: 20
                focus: true
                closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
                background: Surface { border.color: Kirigami.Theme.highlightColor }
                contentItem: ColumnLayout {
                    spacing: 12
                    Controls.Label { color: "#f0f3f6"; text: i18n("VibeEnergy"); font.pointSize: 18; font.weight: Font.DemiBold }
                    Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; text: i18n("Free & open-source Linux energy monitor") }
                    Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#f0f3f6"; text: i18n("Developed by Luke Beslic") }
                    Controls.Label {
                        Layout.fillWidth: true; wrapMode: Text.WrapAnywhere
                        text: "<a href='https://vibeenergy.techtoapes.com/'>vibeenergy.techtoapes.com ↗</a>"
                        textFormat: Text.RichText; linkColor: "#43b8d4"
                        onLinkActivated: link => Qt.openUrlExternally(link)
                        Accessible.name: qsTr("Open the VibeEnergy website")
                    }
                    Controls.Label {
                        Layout.fillWidth: true; wrapMode: Text.WrapAnywhere
                        text: "<a href='https://github.com/Rodgrad/vibeenergy'>GitHub · Source code ↗</a>"
                        textFormat: Text.RichText; linkColor: "#43b8d4"
                        onLinkActivated: link => Qt.openUrlExternally(link)
                        Accessible.name: qsTr("Open the VibeEnergy GitHub repository")
                    }
                    Controls.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#a7b3bf"; text: i18n("Enjoying VibeEnergy? Support its development and future projects with a coffee.") }
                    ActionButton {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("☕  Power Me with Coffee")
                        font.weight: Font.Bold
                        contentItem: RowLayout {
                            spacing: 9
                            Image { source: Qt.resolvedUrl("../icons/coffee.svg"); Layout.preferredWidth: 23; Layout.preferredHeight: 23; fillMode: Image.PreserveAspectFit; Layout.alignment: Qt.AlignVCenter }
                            Controls.Label { text: qsTr("Power Me with Coffee"); color: "#f0f3f6"; font.weight: Font.Bold; Layout.alignment: Qt.AlignVCenter }
                        }
                        Accessible.name: qsTr("Support TechToApes on Ko-fi")
                        background: Rectangle { radius: 8; color: parent.down ? "#bc4010" : parent.hovered ? "#d34d16" : "#e4571d"; border.width: parent.activeFocus ? 2 : 1; border.color: "#ff9b6c" }
                        onClicked: Qt.openUrlExternally("https://ko-fi.com/techtoapes")
                    }
                    Controls.Label { color: "#f0f3f6"; text: "vibeenergy · 1.0.1"; opacity: .65; font.pointSize: 9 }
                    ActionButton { text: i18n("Close"); Layout.alignment: Qt.AlignRight; onClicked: creditsPopup.close() }
                }
            }
        }
        }
        Rectangle {
            visible: dashboard.wide
            anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
            anchors.margins: 24; anchors.topMargin: 116; width: 288; radius: 14
            color: Qt.tint("#202730",Qt.rgba(0,.12,.2,dashboard.turboStrength*.65)); border.color: Qt.tint("#3a4653",Qt.rgba(0,.85,1,dashboard.turboStrength*.85))
            Controls.ScrollView {
                id: sidebarScroll
                objectName: "sidebarScroll"
                anchors.fill: parent; anchors.margins: 16
                clip: true
                rightPadding: 10
                contentWidth: availableWidth
                contentHeight: sidebarContents.height
                Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
                Controls.ScrollBar.vertical: Controls.ScrollBar { width: 6; x: sidebarScroll.width-width; y: 0; height: sidebarScroll.height; policy: Controls.ScrollBar.AsNeeded; active: size<1 }
                ColumnLayout {
                    id: sidebarContents
                    width: sidebarScroll.availableWidth
                    height: implicitHeight
                    spacing: 12
                Repeater {
                    model: [i18n("Overview"), i18n("History"), i18n("Sensors"), i18n("Settings")]
                    delegate: NavigationButton {
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        symbol: ["home","history","cpu","settings"][index]
                        text: modelData; selected: tabs.currentIndex === index
                        onClicked: tabs.currentIndex = index
                    }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#3a4653"; Layout.topMargin: 8; Layout.bottomMargin: 12 }
                TurboButton { id: sidebarTurbo; glow: dashboard.turboStrength; Layout.fillWidth: true; turboActive: dashboard.turboActive; onClicked: dashboard.toggleTurbo() }
                Controls.Label { color: "#f0f3f6"; Layout.fillWidth: true; text: "+1% performance*"; horizontalAlignment: Text.AlignHCenter; font.pointSize: 10 }
                Controls.Label { Layout.fillWidth: true; text: i18n("All power to the GPU for five seconds."); wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; color: "#a7b3bf"; font.pointSize: 9 }
                Controls.Label { Layout.fillWidth: true; text: i18n("Keep Turbo always on in Settings."); wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; color: "#a7b3bf"; font.pointSize: 9 }
                Controls.Label { Layout.fillWidth: true; Layout.preferredHeight: 16; Layout.minimumHeight: 16; Layout.maximumHeight: 16; text: dashboard.turboActive ? (dashboard.alwaysOn ? i18n("⚡ TURBO BOOST ALWAYS ON") : i18n("⚡ TURBO BOOST ACTIVE")) : ""; horizontalAlignment: Text.AlignHCenter; color: "#00d9ff"; font.pointSize: 10; font.weight: Font.DemiBold }
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: 8; Layout.minimumHeight: 8; Layout.maximumHeight: 8; spacing: 4
                    opacity: dashboard.turboStrength
                    Repeater {
                        model: 7
                        delegate: Rectangle {
                            required property int index
                            Layout.fillWidth: true; implicitHeight: 7; radius: 3
                            color: dashboard.turboProgress*7>index ? "#00d9ff" : "#17465e"
                        }
                    }
                    Accessible.name: dashboard.alwaysOn ? i18n("Turbo Boost always on") : i18n("Turbo Boost time remaining: %1 seconds",Math.ceil(dashboard.turboProgress*5))
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#3a4653"; Layout.topMargin: 16; Layout.bottomMargin: 8 }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    AppIcon { kind: "bolt"; ink: "#43b8d4"; Layout.preferredWidth: 26; Layout.preferredHeight: 26 }
                    Controls.Label { Layout.fillWidth: true; text: i18n("Electricity"); color: "#f0f3f6"; font.pointSize: 16; font.weight: Font.DemiBold }
                }
                GridLayout {
                    Layout.fillWidth: true; columns: 2; rowSpacing: 14; columnSpacing: 8
                    Controls.Label { text: i18n("Price (%1/kWh)",root.currency); color: "#d6dfe8"; font.pointSize: 11; Layout.fillWidth: true }
                    Controls.Label {
                        objectName: "sidebarPrice"
                        text: Number(root.snapshot.config ? root.snapshot.config.price : .177).toLocaleString(Qt.locale(),'f',3)
                        color: "#f0f3f6"; font.pointSize: 11
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: 110
                    }
                    Controls.Label { text: i18n("Currency"); color: "#d6dfe8"; font.pointSize: 11; Layout.fillWidth: true }
                    Controls.Label {
                        text: root.currency
                        color: "#f0f3f6"; font.pointSize: 11
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: 110
                    }
                }
                Item { implicitHeight: 8 }

            }
        }
        }
        }

        TurboEffects {
            anchors.fill: parent; z: 9
            objectName: "gpuEnergyFlow"
            borderOnly: true
            // Render outside the scrolling content so the corona is not cut at its top edge.
            readonly property point cardPosition: {
                const scrollY=overviewScroll.contentItem ? overviewScroll.contentItem.contentY : 0
                const layoutWidth=dashboard.width,layoutHeight=dashboard.height
                const cardX=overviewGpuCard.x,cardY=overviewGpuCard.y
                return overviewGpuCard.mapToItem(viewport,0,0)
            }
            readonly property point scrollPosition: {
                const layoutHeight=dashboard.height,layoutWidth=dashboard.width
                return overviewScroll.mapToItem(viewport,0,0)
            }
            strength: tabs.currentIndex===0 && cardPosition.y>=scrollPosition.y-1 && cardPosition.y+overviewGpuCard.height<=scrollPosition.y+overviewScroll.height+1 ? dashboard.turboStrength : 0
            time: dashboard.turboTime
            reducedMotion: dashboard.reducedMotion
            frame: Qt.rect(cardPosition.x,cardPosition.y,overviewGpuCard.width,overviewGpuCard.height)
            origin: Qt.point(cardPosition.x+overviewGpuCard.width,cardPosition.y+overviewGpuCard.height/2)
        }
        TurboEffects {
            anchors.fill: parent; z: 10
            continuous: dashboard.alwaysOn; strength: dashboard.turboStrength; time: dashboard.turboTime; reducedMotion: dashboard.reducedMotion
            frame: Qt.rect(viewport.edgeMargin,viewport.edgeMargin,dashboard.width,dashboard.height)
            origin: dashboard.turboOrigin
            onLightningHit: if(dashboard.turboActive && bridge.turboSoundEnabled && turboAudio.item)turboAudio.item.playStrike()
        }
    }
}
