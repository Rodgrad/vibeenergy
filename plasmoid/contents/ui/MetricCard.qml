pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Surface {
    id: card
    property string title
    property string value
    property string unit
    property string detail
    property bool emphasized: false
    property bool compact: false
    property bool wrapValue: false
    property string symbol: ""
    implicitHeight: compact ? 112 : content.implicitHeight + 36
    color: Qt.tint(emphasized ? "#243443" : "#252d37",Qt.rgba(0,.15,.25,energy*.55))
    ColumnLayout {
        id: content
        anchors.fill: parent; anchors.margins: card.compact ? 14 : 18; spacing: card.compact ? 6 : 10
        RowLayout {
            spacing: 8
            AppIcon { visible: card.symbol!==""; kind: card.symbol; ink: card.emphasized ? "#16c4eb" : "#b2c8dd"; Layout.preferredWidth: 23; Layout.preferredHeight: 23 }
            Controls.Label { Layout.fillWidth: true; text: card.title; color: "#f0f3f6"; opacity: .9; font.pointSize: 11 }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 5
            Controls.Label { color: "#f0f3f6"; text: card.value; font.pointSize: 24; font.weight: Font.DemiBold; elide: card.wrapValue ? Text.ElideNone : Text.ElideRight; wrapMode: card.wrapValue ? Text.Wrap : Text.NoWrap; Layout.fillWidth: true; minimumPointSize: 16; fontSizeMode: card.wrapValue ? Text.FixedSize : Text.HorizontalFit }
            Controls.Label { color: "#f0f3f6"; text: card.unit; opacity: .65; font.pointSize: 11; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 4 }
        }
        Controls.Label { color: "#f0f3f6"; text: card.detail; Layout.fillWidth: true; elide: Text.ElideRight; opacity: .72; font.pointSize: 10 }
    }
}
