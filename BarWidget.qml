import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    readonly property var mainInstance: pluginApi?.mainInstance
    readonly property string state: mainInstance?.backendState || "stopped"
    readonly property string message: mainInstance?.backendMessage || ""

    readonly property string screenName: screen?.name ?? ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

    readonly property real contentWidth: iconItem.width + Style.marginM * 2
    readonly property real contentHeight: capsuleHeight

    implicitWidth: contentWidth
    implicitHeight: contentHeight

    property real pulse: 0
    property int recordingSeconds: 0

    Timer {
        id: recordingTimer
        interval: 1000
        running: root.state === "recording"
        repeat: true
        onTriggered: root.recordingSeconds++
        onRunningChanged: if (!running) root.recordingSeconds = 0
    }

    function formatDuration(secs) {
        var mins = Math.floor(secs / 60);
        var s = secs % 60;
        return mins + ":" + (s < 10 ? "0" : "") + s;
    }

    readonly property string tooltipText: {
        switch (state) {
        case "setup":
            return pluginApi?.tr("widget.setup") || "Installing dependencies...";
        case "recording":
            return (pluginApi?.tr("widget.recording") || "Recording") + " " + formatDuration(recordingSeconds) + " \u2014 click to stop";
        case "transcribing":
            return pluginApi?.tr("widget.transcribing") || "Transcribing...";
        case "starting":
            return pluginApi?.tr("widget.starting") || "Starting backend...";
        case "error":
            return pluginApi?.tr("widget.error", {message: message}) || ("Error: " + message);
        default:
            return pluginApi?.tr("widget.idle") || "Click to start dictation";
        }
    }

    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        color: {
            switch (root.state) {
            case "setup":
                return Color.mPrimaryContainer;
            case "recording":
                return Qt.rgba(Color.mError.r * (1 - pulse * 0.4), Color.mError.g * (1 - pulse * 0.6), Color.mError.b * (1 - pulse * 0.6), Color.mError.a);
            case "transcribing":
                return Qt.rgba(Color.mPrimary.r * (1 - pulse * 0.2), Color.mPrimary.g * (1 - pulse * 0.2), Color.mPrimary.b * (1 - pulse * 0.2), Color.mPrimary.a);
            case "starting":
                return Qt.rgba(Color.mPrimaryContainer.r + (Color.mPrimary.r - Color.mPrimaryContainer.r) * pulse, Color.mPrimaryContainer.g + (Color.mPrimary.g - Color.mPrimaryContainer.g) * pulse, Color.mPrimaryContainer.b + (Color.mPrimary.b - Color.mPrimaryContainer.b) * pulse, Color.mPrimaryContainer.a);
            case "error":
                return Color.mErrorContainer;
            default:
                return mouseArea.containsMouse ? Color.mHover : Style.capsuleColor;
            }
        }
        radius: Style.radiusL
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        NIcon {
            id: iconItem
            anchors.centerIn: parent
            icon: {
                switch (root.state) {
                case "setup": return "download";
                case "recording": return "stop-circle";
                case "transcribing": return "loader";
                case "starting": return "loader";
                case "error": return "alert-triangle";
                default: return "microphone";
                }
            }
            color: {
                switch (root.state) {
                case "setup": return Color.mOnPrimaryContainer;
                case "recording": return Color.mOnError;
                case "transcribing": return Color.mOnPrimary;
                case "starting": return Color.mOnPrimaryContainer;
                case "error": return Color.mOnErrorContainer;
                default: return Color.mOnSurface;
                }
            }

            Behavior on color {
                ColorAnimation { duration: 150 }
            }
        }
    }

    SequentialAnimation on pulse {
        running: root.state === "setup" || root.state === "recording" || root.state === "starting" || root.state === "transcribing"
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.pulse = 0
        NumberAnimation {
            from: 0
            to: 1
            duration: root.state === "recording" ? 600 : 800
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            from: 1
            to: 0
            duration: root.state === "recording" ? 600 : 800
            easing.type: Easing.InOutQuad
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onEntered: TooltipService.show(root, root.tooltipText, BarService.getTooltipDirection())
        onExited: TooltipService.hide()

        onClicked: {
            if (mainInstance) {
                mainInstance.toggleRecording();
            }
        }
    }

    Component.onCompleted: Logger.i("Dictation", "BarWidget loaded")
}
