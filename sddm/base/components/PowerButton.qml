import QtQuick 2.15

Rectangle {
    id: btn
    property string label: ""
    property color fg: "white"
    property color fill: "#222"
    property color ring: "#555"
    property real corner: 12
    property string family: "sans"
    signal activated()

    implicitWidth: caption.implicitWidth + 28
    implicitHeight: 36
    radius: corner
    color: area.containsMouse ? Qt.lighter(fill, 1.25) : fill
    border.color: ring
    border.width: 1
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: caption
        anchors.centerIn: parent
        text: btn.label
        color: btn.fg
        font.family: btn.family
        font.pixelSize: 13
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.activated()
    }
}
