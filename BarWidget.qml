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

    property int recordingSeconds: 0

    readonly property string recordingDurationText: {
        var m = Math.floor(recordingSeconds / 60)
        var s = recordingSeconds % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    Timer {
        id: recordingTimer
        interval: 1000
        running: root.state === "recording"
        repeat: true
        onTriggered: root.recordingSeconds++
        onRunningChanged: if (!running) root.recordingSeconds = 0
    }

    readonly property real contentWidth: layoutRow.implicitWidth + Style.marginM * 2
    readonly property real contentHeight: capsuleHeight

    implicitWidth: contentWidth
    implicitHeight: contentHeight

    readonly property string tooltipText: {
        switch (state) {
        case "setup":
            return pluginApi?.tr("widget.setup") || "Installing dependencies..."
        case "recording":
            return (pluginApi?.tr("widget.recording") || "Recording")
                + " " + recordingDurationText
                + " \u2014 " + (pluginApi?.tr("widget.recordingHint") || "click to stop")
        case "transcribing":
            return pluginApi?.tr("widget.transcribing") || "Transcribing..."
        case "starting":
            return pluginApi?.tr("widget.starting") || "Starting backend..."
        case "error":
            return (pluginApi?.tr("widget.error", {message: message}) || ("Error: " + message))
                + "\n" + (pluginApi?.tr("widget.errorHint") || "click to retry")
        default:
            return pluginApi?.tr("widget.idle") || "Click to start dictation"
        }
    }

    property real pulse: 0

    SequentialAnimation on pulse {
        running: root.state === "recording" || root.state === "starting" || root.state === "transcribing"
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.pulse = 0
        NumberAnimation {
            from: 0; to: 1
            duration: root.state === "recording" ? 600 : 900
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            from: 1; to: 0
            duration: root.state === "recording" ? 600 : 900
            easing.type: Easing.InOutQuad
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
            case "recording":
                return Color.mErrorContainer
            case "transcribing":
                return Color.mPrimaryContainer
            case "starting":
                return Color.mSecondaryContainer
            case "setup":
                return Color.mPrimaryContainer
            case "error":
                return Color.mErrorContainer
            default:
                return mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
            }
        }
        radius: Style.radiusL
        border.color: root.state === "recording"
            ? Color.mError
            : (root.state === "error" ? Color.mError : Style.capsuleBorderColor)
        border.width: root.state === "recording" ? 2 : Style.capsuleBorderWidth

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: {
                switch (root.state) {
                case "recording": return Color.mError
                case "transcribing": return Color.mPrimary
                case "starting": return Color.mPrimary
                default: return "transparent"
                }
            }
            opacity: {
                switch (root.state) {
                case "recording": return pulse * 0.25
                case "transcribing": return pulse * 0.12
                case "starting": return pulse * 0.18
                default: return 0
                }
            }
        }

        RowLayout {
            id: layoutRow
            anchors.centerIn: parent
            spacing: Style.marginS

            NIcon {
                id: iconItem
                icon: {
                    switch (root.state) {
                    case "setup": return "download"
                    case "recording": return "player-stop"
                    case "transcribing": return "loader"
                    case "starting": return "loader"
                    case "error": return "alert-triangle"
                    default:
                        return mouseArea.containsMouse ? "microphone-filled" : "microphone"
                    }
                }
                color: {
                    switch (root.state) {
                    case "setup": return Color.mOnPrimaryContainer
                    case "recording": return Color.mOnErrorContainer
                    case "transcribing": return Color.mOnPrimaryContainer
                    case "starting": return Color.mOnSecondaryContainer
                    case "error": return Color.mOnErrorContainer
                    default:
                        return mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
                    }
                }
                applyUiScale: false

                RotationAnimator on rotation {
                    running: root.state === "transcribing" || root.state === "starting"
                    from: 0; to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
                Binding {
                    target: iconItem
                    property: "rotation"
                    value: 0
                    when: root.state !== "transcribing" && root.state !== "starting"
                }

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }

            NText {
                visible: root.state === "recording"
                text: root.recordingDurationText
                color: Color.mOnErrorContainer
                pointSize: root.barFontSize
                applyUiScale: false
                font.weight: Font.Medium
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onEntered: TooltipService.show(root, root.tooltipText, BarService.getTooltipDirection(screenName))
        onExited: TooltipService.hide()

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                PanelService.showContextMenu(contextMenu, root, screen)
                return
            }
            if (mainInstance) {
                mainInstance.toggleRecording()
            }
        }
    }

    NPopupContextMenu {
        id: contextMenu

        model: [
            {
                "label": pluginApi?.tr("context.toggle") || "Toggle Dictation",
                "action": "toggle-dictation",
                "icon": "microphone"
            },
            {
                "label": pluginApi?.tr("context.settings") || "Settings",
                "action": "open-settings",
                "icon": "settings"
            }
        ]

        onTriggered: action => {
            contextMenu.close()
            PanelService.closeContextMenu(screen)

            if (action === "toggle-dictation") {
                if (mainInstance) {
                    mainInstance.toggleRecording()
                }
            } else if (action === "open-settings") {
                if (pluginApi?.manifest) {
                    BarService.openPluginSettings(screen, pluginApi.manifest)
                }
            }
        }
    }

    Component.onCompleted: Logger.i("Dictation", "BarWidget loaded")
}
