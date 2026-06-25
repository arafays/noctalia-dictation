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

    property var cfg: pluginApi?.pluginSettings || ({})
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

    readonly property bool showOverlay: cfg.showOverlay ?? defaults.showOverlay ?? true
    readonly property bool autoType: cfg.autoType ?? defaults.autoType ?? true
    readonly property bool vadEnabled: cfg.vadEnabled ?? defaults.vadEnabled ?? true

    readonly property string screenName: screen?.name ?? ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)

    readonly property real contentWidth: layoutRow.implicitWidth + Style.marginM * 2
    readonly property real contentHeight: capsuleHeight

    implicitWidth: contentWidth
    implicitHeight: contentHeight

    function saveQuickSetting(key, value) {
        if (!pluginApi) return
        pluginApi.pluginSettings[key] = value
        pluginApi.saveSettings()
        var backendKeys = ["autoType", "vadEnabled", "vadThreshold"]
        if (backendKeys.indexOf(key) >= 0 && mainInstance) {
            mainInstance.updateSettings()
        }
    }

    function openSettings() {
        if (pluginApi?.manifest) {
            BarService.openPluginSettings(screen, pluginApi.manifest)
        }
    }

    readonly property string tooltipText: {
        switch (state) {
        case "setup":
            return pluginApi?.tr("widget.setup") || "Installing dependencies..."
        case "recording":
            return (pluginApi?.tr("widget.recording") || "Listening")
                + " — " + (pluginApi?.tr("widget.recordingHint") || "click to stop")
        case "transcribing":
            return (pluginApi?.tr("widget.transcribing") || "Transcribing...")
                + " — " + (pluginApi?.tr("widget.recordingHint") || "click to stop")
        case "starting":
            return pluginApi?.tr("widget.starting") || "Starting backend..."
        case "error":
            return (pluginApi?.tr("widget.error", {message: message}) || ("Error: " + message))
                + "\n" + (pluginApi?.tr("widget.errorHint") || "click to retry")
        case "idle":
            if (message === "no_speech") {
                return pluginApi?.tr("widget.noSpeech") || "No speech detected"
            }
            return pluginApi?.tr("widget.idle") || "Click to start dictation"
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
                    case "recording": return "player-record-filled"
                    case "transcribing": return "loader"
                    case "starting": return "loader"
                    case "error": return "alert-triangle-filled"
                    default:
                        return "microphone"
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
                    running: root.state === "starting" || root.state === "transcribing"
                    from: 0; to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
                Binding {
                    target: iconItem
                    property: "rotation"
                    value: 0
                    when: root.state !== "starting" && root.state !== "transcribing"
                }

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
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
                "label": pluginApi?.tr("context.openPanel") || "Open history panel",
                "action": "open-panel",
                "icon": "history"
            },
            {
                "label": (root.showOverlay
                    ? (pluginApi?.tr("context.overlayOn") || "Live overlay: on")
                    : (pluginApi?.tr("context.overlayOff") || "Live overlay: off")),
                "action": "toggle-overlay",
                "icon": root.showOverlay ? "eye" : "eye-off"
            },
            {
                "label": (root.autoType
                    ? (pluginApi?.tr("context.autoTypeOn") || "Auto-type: on")
                    : (pluginApi?.tr("context.autoTypeOff") || "Auto-type: off")),
                "action": "toggle-auto-type",
                "icon": "keyboard"
            },
            {
                "label": (root.vadEnabled
                    ? (pluginApi?.tr("context.vadOn") || "Noise gate (VAD): on")
                    : (pluginApi?.tr("context.vadOff") || "Noise gate (VAD): off")),
                "action": "toggle-vad",
                "icon": "filter"
            },
            {
                "label": pluginApi?.tr("actions.widget-settings") || I18n.tr("actions.widget-settings"),
                "action": "widget-settings",
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
            } else if (action === "open-panel") {
                pluginApi?.openPanel(screen, root)
            } else if (action === "toggle-overlay") {
                root.saveQuickSetting("showOverlay", !root.showOverlay)
            } else if (action === "toggle-auto-type") {
                root.saveQuickSetting("autoType", !root.autoType)
            } else if (action === "toggle-vad") {
                root.saveQuickSetting("vadEnabled", !root.vadEnabled)
            } else if (action === "widget-settings") {
                root.openSettings()
            }
        }
    }

    Component.onCompleted: Logger.i("Dictation", "BarWidget loaded")
}
