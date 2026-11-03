pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

Surface {
    id: card
    property string title
    property string symbol: "calendar"
    property string energyValue: "—"
    property string energyUnit: "kWh"
    property var costs: ({})
    property string currency: "EUR"
    property color accent: "#35c76a"
    property bool emphasized: false
    property string statusText
    property color statusColor: "#a7b3bf"
    readonly property var costEntries: {
        const codes=Object.keys(costs).sort()
        return codes.length ? codes.map(code => ({currency:code, cost:costs[code]})) : [{currency:currency,cost:null}]
    }
    color: Qt.tint("#252d37",Qt.rgba(0,.15,.25,energy*.55))
    border.color: energy > 0 ? "#43b8d4" : "#3a4653"
    implicitHeight: Math.max(104,content.implicitHeight+20)
    ColumnLayout {
        id: content
        anchors.fill: parent; anchors.margins: 10; spacing: 4
        RowLayout {
            spacing: 7
            AppIcon { kind: card.symbol; ink: card.accent; Layout.preferredWidth: card.emphasized ? 22 : 17; Layout.preferredHeight: card.emphasized ? 22 : 17 }
            Controls.Label { text: card.title; color: card.emphasized ? "#f0fff5" : "#d6dfe8"; font.pointSize: card.emphasized ? 15 : 10; font.weight: card.emphasized ? Font.DemiBold : Font.Normal; Layout.fillWidth: true }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            ColumnLayout {
                spacing: 0
                Controls.Label { text: card.energyValue; color: card.emphasized ? card.accent : "#f0f3f6"; font.pointSize: 22; font.weight: Font.DemiBold }
                Controls.Label { text: card.energyUnit; color: "#a7b3bf"; font.pointSize: 13 }
            }
            Rectangle { implicitWidth: 1; Layout.preferredHeight: 34; color: "#3a4653" }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 3
                Repeater {
                    model: card.costEntries
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true; spacing: 5
                        Controls.Label {
                            Layout.fillWidth: true
                            text: modelData.cost === null ? "—" : Number(modelData.cost).toFixed(3)
                            horizontalAlignment: Text.AlignRight
                            color: card.emphasized ? "#b8ff62" : card.accent; font.pointSize: card.emphasized ? 40 : 30; font.weight: Font.Bold
                            fontSizeMode: Text.HorizontalFit; minimumPointSize: card.emphasized ? 34 : 22
                        }
                        Controls.Label { text: modelData.currency; color: card.emphasized ? "#b8ff62" : card.accent; font.pointSize: card.emphasized ? 22 : 15; font.weight: card.emphasized ? Font.DemiBold : Font.Normal; Layout.alignment: Qt.AlignBaseline }
                    }
                }
            }
        }
        RowLayout {
            spacing: 6
            Rectangle { implicitWidth: 5; implicitHeight: 5; radius: 3; color: card.statusColor }
            Controls.Label { text: card.statusText; color: "#a7b3bf"; font.pointSize: 9; Layout.fillWidth: true; wrapMode: Text.Wrap }
        }
    }
}
