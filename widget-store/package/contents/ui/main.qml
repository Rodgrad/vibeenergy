pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami
import "Metrics.js" as Metrics

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation
    readonly property color foreground: "#f0f3f6"
    readonly property color surface: "#171c23"
    readonly property var accents: ["#43b8d4","#70dba1","#b79be8"]
    readonly property var costAccents: ["#a4ffca","#43cbe8","#b79be8"]
    component ActionButton: Controls.Button {
        implicitHeight:34;leftPadding:12;rightPadding:12
        background:Rectangle {color:parent.down?"#303b48":"#202730";radius:6;border.color:parent.activeFocus?"#43b8d4":"#3a4653"}
        contentItem:Text {text:parent.text;color:"#f0f3f6";font:parent.font;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter}
    }
    property var livePoints: []
    property var snapshot: ({})
    property bool inFlight: false
    property bool hasSnapshot: false
    readonly property real startedAt: Date.now()/1000
    property real lastRefresh: startedAt
    property var lastSnapshotTimestamp: null
    property real now: Date.now()/1000
    property string readError: ""
    readonly property var devices: Array.isArray(snapshot.devices) ? snapshot.devices : []
    readonly property var daily: Array.isArray(snapshot.daily) ? snapshot.daily : []
    readonly property string currency: snapshot.config && /^[A-Z]{3}$/.test(snapshot.config.currency) ? snapshot.config.currency : "EUR"
    readonly property bool fresh: Metrics.isFresh(snapshot,now)
    readonly property bool showWarning: !fresh && Metrics.warningDue(lastRefresh,now)
    readonly property string noticeTitle: qsTr("You need the VibeEnergy app installed and running.")
    readonly property string today: Metrics.day(new Date(now*1000))
    readonly property string snapshotCommand: "/bin/sh -c 'cat -- \"${XDG_STATE_HOME:-$HOME/.local/state}/energytlk/state.json\"'"
    property bool turboReadInFlight: false
    property string turboSettings: ""
    readonly property var turbo: Metrics.turboState(turboSettings,now)
    property real turboTime: 0
    readonly property bool reducedMotion: Kirigami.Units.longDuration<=1
    readonly property string turboCommand: "/bin/sh -c 'cat -- \"${XDG_CONFIG_HOME:-$HOME/.config}/energytlk/appearance.ini\" 2>/dev/null; printf \"\\n---VIBEENERGY-TURBO---\\n\"; cat -- \"${XDG_STATE_HOME:-$HOME/.local/state}/energytlk/turbo.json\" 2>/dev/null'"
    NumberAnimation {target:root;property:"turboTime";from:0;to:86400;duration:86400000;loops:Animation.Infinite;running:root.turbo.active && !root.reducedMotion && root.visible}
    Plasma5Support.DataSource {
        id:turboReader
        engine:"executable"
        connectedSources:[]
        onNewData:(sourceName,data)=> {
            disconnectSource(sourceName)
            root.turboReadInFlight=false
            root.turboSettings=String(data.stdout || "")
        }
    }
    function refresh() {
        now=Date.now()/1000
        if(!turboReadInFlight) {turboReadInFlight=true;turboReader.connectSource(turboCommand)}
        if(!inFlight) {inFlight=true;reader.connectSource(snapshotCommand)}
    }
    function power(kind) {
        const value=Metrics.watts(devices,kind)
        return fresh && value!==null ? value.toFixed(1)+" W" : "—"
    }
    Plasma5Support.DataSource {
        id: reader
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName,data) => {
            disconnectSource(sourceName);root.inFlight=false
            if(data['exit code']!==0) {root.snapshot={};root.hasSnapshot=false;root.readError=qsTr("Waiting for VibeEnergy readings.");return}
            try {
                const value=JSON.parse(String(data.stdout))
                if(!value || typeof value!=="object" || Array.isArray(value))throw new Error("Invalid snapshot")
                if(typeof value.timestamp==="number" && isFinite(value.timestamp) && value.timestamp<=Date.now()/1000+5 && value.timestamp!==root.lastSnapshotTimestamp) {
                    root.lastSnapshotTimestamp=value.timestamp
                    root.lastRefresh=Math.max(root.startedAt,Math.min(Date.now()/1000,value.timestamp))
                }
                if(Metrics.isFresh(value,root.now) && (!root.livePoints.length || root.livePoints[root.livePoints.length-1].timestamp!==value.timestamp)) {
                    const points=root.livePoints.slice(-119)
                    points.push({timestamp:value.timestamp,cpu:Metrics.watts(value.devices || [],"cpu"),gpu:Metrics.watts(value.devices || [],"gpu")})
                    root.livePoints=points
                }
                root.snapshot=value;root.hasSnapshot=true;root.readError=""
            } catch(error) {root.snapshot={};root.hasSnapshot=false;root.readError=qsTr("Waiting for valid VibeEnergy readings.")}

        }
    }
    Timer {interval:1000;running:true;repeat:true;onTriggered:root.refresh()}
    Component.onCompleted: root.refresh()
    toolTipMainText: "VibeEnergy"
    toolTipSubText: root.fresh ? "CPU: "+root.power('cpu')+" · GPU: "+root.power('gpu') : root.showWarning ? root.noticeTitle : qsTr("Waiting for readings…")
    compactRepresentation: Item {
        implicitWidth:root.fresh?compactRow.implicitWidth+12:260
        implicitHeight:root.fresh?compactRow.implicitHeight+8:38
        Layout.minimumWidth:implicitWidth
        Layout.minimumHeight:30
        Rectangle {anchors.fill:parent;visible:root.showWarning;radius:6;color:"#352c18";border.color:"#d6ae68"}
        RowLayout {
            id: compactRow;anchors.fill:parent;anchors.margins:6;spacing:6
            Image {source:Qt.resolvedUrl("../icons/vibeenergy.svg");Layout.preferredWidth:22;Layout.preferredHeight:22}
            Controls.Label {color:root.showWarning?"#ffe09a":root.foreground;text:root.fresh?root.power(''):root.showWarning?root.noticeTitle:qsTr("Waiting for readings…");font.bold:root.showWarning;font.pointSize:9;Layout.fillWidth:true;wrapMode:Text.WordWrap;textFormat:Text.PlainText}
        }
        TurboEffects {anchors.fill:parent;strength:root.turbo.active?1:0;time:root.turboTime;continuous:root.turbo.continuous;reducedMotion:root.reducedMotion;frame:Qt.rect(4,4,width-8,height-8)}
        MouseArea {anchors.fill:parent;onClicked:root.expanded=!root.expanded}
    }
    fullRepresentation: Item {
        readonly property int effectMargin: 28
        implicitWidth:680;implicitHeight:486+(requirementBanner.visible?requirementBanner.implicitHeight+12:0)
        Layout.minimumWidth:620;Layout.minimumHeight:456+(requirementBanner.visible?requirementBanner.implicitHeight+12:0)
        Rectangle {anchors.fill:parent;anchors.margins:parent.effectMargin;color:root.surface;radius:14}
        TurboEffects {anchors.fill:parent;strength:root.turbo.active?1:0;time:root.turboTime;continuous:root.turbo.continuous;reducedMotion:root.reducedMotion;backgroundLayer:true;frame:Qt.rect(parent.effectMargin,parent.effectMargin,width-2*parent.effectMargin,height-2*parent.effectMargin)}
        TurboEffects {anchors.fill:parent;z:10;strength:root.turbo.active?1:0;time:root.turboTime;continuous:root.turbo.continuous;reducedMotion:root.reducedMotion;frame:Qt.rect(parent.effectMargin,parent.effectMargin,width-2*parent.effectMargin,height-2*parent.effectMargin)}
        ColumnLayout {
        id: panel
        anchors.fill:parent;anchors.margins:parent.effectMargin+12
        spacing:12
        RowLayout {
            Layout.fillWidth:true;spacing:8
            Image {source:Qt.resolvedUrl("../icons/vibeenergy.svg");Layout.preferredWidth:28;Layout.preferredHeight:28}
            Controls.Label {color:root.foreground;text:"VibeEnergy";font.pointSize:16;font.bold:true;Layout.fillWidth:true}
            Rectangle {implicitWidth:7;implicitHeight:7;radius:4;color:root.fresh?"#35c76a":"#d6ae68"}
            Controls.Label {color:root.foreground;text:root.fresh?qsTr("Recording"):qsTr("Offline");font.pointSize:9}
        }
        Rectangle {
            id: requirementBanner
            objectName: "appRequirementBanner"
            visible: root.showWarning
            Layout.fillWidth:true
            implicitHeight:requirementText.implicitHeight+20
            radius:8;color:root.fresh?"#183342":"#352c18";border.color:root.fresh?"#43b8d4":"#d6ae68"
            ColumnLayout {
                id:requirementText
                anchors.fill:parent;anchors.margins:10;spacing:4
                Controls.Label {Layout.fillWidth:true;wrapMode:Text.Wrap;color:"#ffe09a";font.bold:true;font.pointSize:12;text:root.noticeTitle}
            }
        }
        RowLayout {
            Layout.fillWidth:true;spacing:8
            Repeater {
                model:["CPU","GPU",qsTr("Total")]
                delegate: PowerCard {
                    required property int index
                    required property string modelData
                    Layout.fillWidth:true
                    Layout.minimumWidth:0
                    title:modelData
                    iconKind:index===0?"cpu":index===1?"gpu":"bolt"
                    accent:root.accents[index]
                    value:root.power(index===0?"cpu":index===1?"gpu":"")
                    available:root.fresh && Metrics.watts(root.devices,index===0?"cpu":index===1?"gpu":"")!==null
                    detail:available?qsTr("Live power"):qsTr("Unavailable")
                    trend:root.livePoints
                    energy:root.turbo.active?1:0
                }
            }
        }
        Repeater {
            model:3
            delegate: RowLayout {
                required property int index
                readonly property var totals:Metrics.summary(root.daily,root.currency,index===0?root.today:index===1?root.today.slice(0,7)+'-01':'0000-01-01',root.today)
                Layout.fillWidth:true
                Controls.Label {color:root.foreground;text:[qsTr("Today"),qsTr("This month"),qsTr("All time")][index];Layout.preferredWidth:95}
                Controls.Label {color:root.foreground;text:totals.hasEnergy?totals.kwh.toFixed(3)+" kWh":"—";textFormat:Text.PlainText;Layout.fillWidth:true;horizontalAlignment:Text.AlignRight;font.pointSize:11}
                Controls.Label {text:(totals.hasCost?totals.cost.toFixed(3):"—")+" "+root.currency;textFormat:Text.PlainText;color:root.costAccents[index];font.pointSize:16;font.bold:true;Layout.preferredWidth:135;horizontalAlignment:Text.AlignRight}
            }
        }
        Controls.Label {
            Layout.fillWidth:true;wrapMode:Text.Wrap;color:root.foreground;opacity:.7;font.pointSize:9
            text:root.readError || qsTr("Read-only companion. Manage recording, price and currency in the VibeEnergy app. CPU/GPU component energy only; not whole-PC wall power.")
        }
        RowLayout {
            Layout.fillWidth:true
            ActionButton {text:qsTr("Refresh");onClicked:root.refresh()}
            Item {Layout.fillWidth:true}
            ActionButton {text:qsTr("Get VibeEnergy");onClicked:Qt.openUrlExternally("https://github.com/Rodgrad/vibeenergy/releases")}
        }
        }
    }
}
