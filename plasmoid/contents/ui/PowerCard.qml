pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

Surface {
    id: card
    property string title
    property string value
    property string detail
    property string iconKind
    property color accent: "#43b8d4"
    property var trend: []
    property bool available: true
    property bool activation: false
    property string activationText: qsTr("Activate CPU")
    signal activateRequested()
    implicitHeight: activation ? 156 : 138
    color: Qt.tint(iconKind === "gpu" ? "#202c29" : iconKind === "bolt" ? "#272735" : "#202831",Qt.rgba(iconKind === "bolt" ? .08 : 0,iconKind === "gpu" ? .18 : .1,iconKind === "gpu" ? .1 : .2,energy*.5))
    border.color: Qt.tint(available ? Qt.rgba(accent.r,accent.g,accent.b,.5) : "#3a4653",Qt.rgba(accent.r,accent.g,accent.b,energy*.8))
    // Static green bloom follows the existing Turbo fade; no extra animation timer.
    Repeater {
        model: card.iconKind==="gpu" && card.energy>.001 ? 18 : 0
        Rectangle {
            required property int index
            anchors.fill: parent
            anchors.margins: -index
            radius: card.radius+index
            color: "transparent"
            border.width: 2
            border.color: index===0 ? "#b5ffce" : "#29ff70"
            opacity: card.energy * (index===0 ? 1 : .48*Math.exp(-index/5))
            visible: opacity>.001
        }
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: 2; radius: card.radius-2
        visible: card.iconKind==="gpu" && opacity>.001
        opacity: card.energy
        gradient: Gradient {
            GradientStop { position: 0; color: "#6535ff78" }
            GradientStop { position: 1; color: "#1829ff70" }
        }
    }
    Sparkline { visible: card.available && (card.iconKind==="gpu" || card.iconKind==="cpu" || card.iconKind==="bolt"); channel: card.iconKind==="bolt" ? "total" : card.iconKind; ink: card.accent; anchors.right: parent.right; anchors.rightMargin: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 34; width: 76; height: 44; points: card.trend }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 6
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            AppIcon { kind: card.iconKind; ink: card.available ? card.accent : "#a7b3bf"; Layout.preferredWidth: 25; Layout.preferredHeight: 25 }
            Controls.Label { text: card.title; color: "#f0f3f6"; font.pointSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
        }
        Controls.Label { Layout.rightMargin: (card.iconKind==="gpu" || card.iconKind==="cpu" || card.iconKind==="bolt") && card.available && card.trend.length>1 ? 80 : 0; text: card.value; color: "#f0f3f6"; font.pointSize: 30; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight; minimumPointSize: 18; fontSizeMode: Text.HorizontalFit }
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            Rectangle { width: 7; height: 7; radius: 4; color: card.available ? card.accent : "#a7b3bf" }
            Controls.Label { text: card.detail; color: card.available && card.iconKind === "gpu" ? card.accent : "#a7b3bf"; Layout.fillWidth: true; font.pointSize: 10; elide: Text.ElideRight }
            ActionButton { visible: card.activation; text: card.activationText; primary: true; implicitHeight: 34; font.weight: Font.DemiBold; onClicked: card.activateRequested() }
        }
    }
}
