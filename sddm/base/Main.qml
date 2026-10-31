import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Effects
import SddmComponents 2.0 as Sddm
import "components"

// One greeter, four layouts (theme.conf `variant`):
//   card     centred glass card: avatar, name, password   (material shells)
//   minimal  big clock bottom-left, password under it     (quiet shells)
//   terminal sharp-cornered prompt block                  (omarchy-style)
//   dots     pure black, dot-matrix clock, one accent     (glyph)
Rectangle {
    id: root
    width: 1920
    height: 1080
    color: pal.background

    Palette { id: pal }

    readonly property bool isCard: pal.variant === "card"
    readonly property bool isMinimal: pal.variant === "minimal"
    readonly property bool isTerminal: pal.variant === "terminal"
    readonly property bool isDots: pal.variant === "dots"
    readonly property real corner: isTerminal ? 0 : pal.radius

    property bool failed: false
    property string clockText: Qt.formatTime(new Date(), pal.clock24 ? "HH:mm" : "h:mm AP")
    property string dateText: Qt.formatDate(new Date(), "dddd, d MMMM")

    function userAt(i) {
        return userModel.data(userModel.index(i, 0), Qt.UserRole + 1);
    }
    function login() {
        if (passwordField.text === "") return;
        sddm.login(userAt(userBox.currentIndex), passwordField.text, sessionBox.currentIndex);
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.clockText = Qt.formatTime(new Date(), pal.clock24 ? "HH:mm" : "h:mm AP");
            root.dateText = Qt.formatDate(new Date(), "dddd, d MMMM");
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.failed = true;
            passwordField.text = "";
            passwordField.forceActiveFocus();
            shake.restart();
        }
        function onLoginSucceeded() { root.failed = false; }
    }

    // ── Wallpaper ────────────────────────────────────────────────────────────
    Image {
        id: wallpaper
        anchors.fill: parent
        source: "assets/background.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: !root.isDots && status === Image.Ready
        layer.enabled: pal.blur && root.isCard
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 0.6
            blurMax: 48
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: !root.isDots
        color: pal.background
        opacity: root.isMinimal ? 0.35 : 0.45
    }

    // ── Clock ────────────────────────────────────────────────────────────────
    Column {
        id: clockBlock
        spacing: 4
        visible: !root.isCard
        anchors {
            left: parent.left
            bottom: parent.bottom
            leftMargin: root.isDots ? 120 : 96
            bottomMargin: root.isDots ? 420 : 380
        }
        Text {
            text: root.clockText
            color: root.isDots ? pal.text : pal.text
            font.family: root.isDots ? "Doto" : pal.fontFamily
            font.pixelSize: root.isDots ? 220 : (root.isTerminal ? 120 : 168)
            font.weight: root.isDots ? Font.Black : Font.Light
        }
        Text {
            text: root.isTerminal ? "$ date  # " + root.dateText.toLowerCase() : root.dateText
            color: root.isDots ? pal.outline : pal.secondary
            font.family: pal.fontFamily
            font.pixelSize: pal.fontSize + 6
            leftPadding: 8
        }
    }

    // ── Login panel ──────────────────────────────────────────────────────────
    Rectangle {
        id: panel
        width: root.isCard ? 420 : 460
        height: panelColumn.implicitHeight + 64
        radius: root.isCard ? pal.cardRadius : root.corner
        color: root.isDots ? "transparent" : Qt.rgba(pal.surfaceContainer.r, pal.surfaceContainer.g, pal.surfaceContainer.b, root.isCard ? 0.82 : 0.9)
        border.color: root.isTerminal ? pal.primary : (root.isCard ? Qt.rgba(pal.outline.r, pal.outline.g, pal.outline.b, 0.3) : "transparent")
        border.width: root.isTerminal ? 2 : (root.isCard ? 1 : 0)
        anchors.horizontalCenter: root.isCard ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.isCard ? parent.verticalCenter : undefined
        x: root.isCard ? 0 : clockBlock.x
        y: root.isCard ? 0 : clockBlock.y + clockBlock.height + 40

        transform: Translate { id: nudge }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: nudge; property: "x"; to: -14; duration: 60 }
            NumberAnimation { target: nudge; property: "x"; to: 14; duration: 90 }
            NumberAnimation { target: nudge; property: "x"; to: -8; duration: 70 }
            NumberAnimation { target: nudge; property: "x"; to: 0; duration: 60 }
        }

        Column {
            id: panelColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 32 }
            spacing: 16

            // Avatar: the user's face when staged, else an initial.
            Rectangle {
                id: avatar
                visible: root.isCard
                width: 96
                height: 96
                radius: width / 2
                anchors.horizontalCenter: parent.horizontalCenter
                color: pal.primary
                Rectangle {
                    id: avatarMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                    layer.enabled: true
                }
                Image {
                    id: avatarImage
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: avatarMask
                    }
                    source: "assets/avatar.png"
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: avatarImage.status !== Image.Ready
                    text: root.userAt(userBox.currentIndex) ? String(root.userAt(userBox.currentIndex)).charAt(0).toUpperCase() : "?"
                    color: pal.onPrimary
                    font.family: pal.fontFamily
                    font.pixelSize: 44
                }
            }

            Text {
                visible: root.isCard
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.clockText
                color: pal.text
                font.family: pal.fontFamily
                font.pixelSize: 44
                font.weight: Font.Light
            }

            ComboBox {
                id: userBox
                width: parent.width
                model: userModel
                textRole: "name"
                currentIndex: userModel.lastIndex
                font.family: pal.fontFamily
                font.pixelSize: pal.fontSize
                visible: userModel.count > 1
                background: Rectangle { radius: root.corner; color: pal.surfaceVariant }
                contentItem: Text {
                    leftPadding: 12
                    verticalAlignment: Text.AlignVCenter
                    text: userBox.displayText
                    color: pal.text
                    font: userBox.font
                }
            }
            Text {
                visible: userModel.count <= 1
                width: parent.width
                horizontalAlignment: root.isCard ? Text.AlignHCenter : Text.AlignLeft
                text: (root.isTerminal ? "login: " : "") + (root.userAt(0) || "")
                color: pal.secondary
                font.family: pal.fontFamily
                font.pixelSize: pal.fontSize + 2
            }

            TextField {
                id: passwordField
                width: parent.width
                height: 48
                echoMode: TextInput.Password
                passwordCharacter: root.isDots ? "•" : "●"
                placeholderText: root.failed ? "Wrong password" : (root.isTerminal ? "password:" : "Password")
                placeholderTextColor: root.failed ? pal.error : pal.outline
                color: pal.text
                font.family: pal.fontFamily
                font.pixelSize: pal.fontSize + 2
                leftPadding: 18
                focus: true
                background: Rectangle {
                    radius: root.isCard ? height / 2 : root.corner
                    color: pal.surfaceVariant
                    border.width: 2
                    border.color: root.failed ? pal.error : (passwordField.activeFocus ? pal.primary : "transparent")
                }
                onAccepted: root.login()
                onTextChanged: root.failed = false
            }

            Row {
                spacing: 8
                width: parent.width
                ComboBox {
                    id: sessionBox
                    width: parent.width - loginButton.width - 8
                    height: 36
                    model: sessionModel
                    textRole: "name"
                    currentIndex: sessionModel.lastIndex
                    font.family: pal.fontFamily
                    font.pixelSize: pal.fontSize - 1
                    background: Rectangle { radius: root.corner; color: "transparent"; border.color: pal.outline; border.width: 1 }
                    contentItem: Text {
                        leftPadding: 12
                        verticalAlignment: Text.AlignVCenter
                        text: sessionBox.displayText
                        color: pal.secondary
                        font: sessionBox.font
                        elide: Text.ElideRight
                    }
                }
                PowerButton {
                    id: loginButton
                    label: "Log in"
                    fg: pal.onPrimary
                    fill: pal.primary
                    ring: pal.primary
                    corner: root.corner
                    family: pal.fontFamily
                    onActivated: root.login()
                }
            }
        }
    }

    // ── Power ────────────────────────────────────────────────────────────────
    Row {
        spacing: 10
        anchors { right: parent.right; bottom: parent.bottom; margins: 40 }
        PowerButton {
            visible: sddm.canSuspend
            label: "Sleep"; fg: pal.text; fill: pal.surfaceContainer; ring: pal.outline
            corner: root.corner; family: pal.fontFamily
            onActivated: sddm.suspend()
        }
        PowerButton {
            visible: sddm.canReboot
            label: "Restart"; fg: pal.text; fill: pal.surfaceContainer; ring: pal.outline
            corner: root.corner; family: pal.fontFamily
            onActivated: sddm.reboot()
        }
        PowerButton {
            visible: sddm.canPowerOff
            label: "Shut down"; fg: pal.text; fill: pal.surfaceContainer; ring: pal.error
            corner: root.corner; family: pal.fontFamily
            onActivated: sddm.powerOff()
        }
    }

    Text {
        anchors { left: parent.left; bottom: parent.bottom; margins: 40 }
        text: pal.shellName
        color: pal.outline
        font.family: pal.fontFamily
        font.pixelSize: pal.fontSize
        font.letterSpacing: 2
        font.capitalization: Font.AllUppercase
    }

    Component.onCompleted: passwordField.forceActiveFocus()
}
