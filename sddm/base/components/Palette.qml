import QtQuick 2.15

// Reads theme.conf(.user) through SDDM's `config` object; every key has a default
// so a half-written palette still renders.
QtObject {
    function str(key, fallback) {
        var v = config[key];
        return (v === undefined || v === "") ? fallback : String(v).replace(/^"|"$/g, "");
    }
    function num(key, fallback) {
        var v = parseFloat(config[key]);
        return isNaN(v) ? fallback : v;
    }
    function flag(key, fallback) {
        var v = config[key];
        if (v === undefined || v === "") return fallback;
        return String(v) === "true";
    }

    readonly property string variant: str("variant", "card")
    readonly property string shellName: str("shellName", "dcli")
    readonly property string fontFamily: str("fontFamily", "Inter")
    readonly property real fontSize: num("fontSize", 14)
    readonly property real radius: num("radius", 14)
    readonly property real cardRadius: num("cardRadius", 28)
    readonly property bool clock24: flag("clock24", true)
    readonly property bool blur: flag("blur", true)
    readonly property color background: str("background", "#111318")
    readonly property color surface: str("surface", "#111318")
    readonly property color surfaceContainer: str("surfaceContainer", "#1d2024")
    readonly property color surfaceVariant: str("surfaceVariant", "#43474e")
    readonly property color text: str("text", "#e2e2e9")
    readonly property color primary: str("primary", "#a8c8ff")
    readonly property color onPrimary: str("onPrimary", "#062e6f")
    readonly property color secondary: str("secondary", "#bec6dc")
    readonly property color tertiary: str("tertiary", "#ddbce0")
    readonly property color error: str("error", "#ffb4ab")
    readonly property color outline: str("outline", "#8d9199")
}
