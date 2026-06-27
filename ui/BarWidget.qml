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
    readonly property string dictationState: mainInstance?.backendState || "stopped"
    readonly property string message: mainInstance?.backendMessage || ""

    property var cfg: pluginApi?.pluginSettings || ({})
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

    readonly property bool showOverlay: cfg.showOverlay ?? defaults.showOverlay ?? true
    readonly property bool autoType: cfg.autoType ?? defaults.autoType ?? true
    readonly property bool vadEnabled: cfg.vadEnabled ?? defaults.vadEnabled ?? true
    readonly property string engine: cfg.engine ?? defaults.engine ?? "auto"
    readonly property string stopHotkeyHint: cfg.stopHotkeyHint ?? defaults.stopHotkeyHint ?? ""
    readonly property bool isFwEngine: root.engine === "faster_whisper"

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

    function openSettingsEntry(entryPoint) {
        if (!pluginApi?.manifest) return
        var popupMenuWindow = PanelService.getPopupMenuWindow(screen)
        if (!popupMenuWindow) {
            Logger.e("Dictation", "No popup menu window for settings")
            return
        }
        var component = Qt.createComponent(Quickshell.shellDir + "/Widgets/NPluginSettingsPopup.qml")
        function instantiateAndOpen() {
            var dialog = component.createObject(popupMenuWindow.dialogParent, {
                "showToastOnSave": true,
                "screen": screen
            })
            if (!dialog) {
                Logger.e("Dictation", "Failed to create settings dialog")
                return
            }
            popupMenuWindow.hasDialog = true
            dialog.closed.connect(() => {
                popupMenuWindow.hasDialog = false
                popupMenuWindow.close()
                dialog.destroy()
            })
            popupMenuWindow.open()
            dialog.openPluginSettings(pluginApi.manifest, entryPoint || "settings")
        }
        if (component.status === Component.Ready) {
            instantiateAndOpen()
        } else if (component.status === Component.Error) {
            Logger.e("Dictation", "Error loading settings dialog:", component.errorString())
        } else {
            component.statusChanged.connect(function () {
                if (component.status === Component.Ready) {
                    instantiateAndOpen()
                } else if (component.status === Component.Error) {
                    Logger.e("Dictation", "Error loading settings dialog:", component.errorString())
                }
            })
        }
    }

    function openPluginSettings() {
        if (!pluginApi?.manifest?.entryPoints?.settings) return
        BarService.openPluginSettings(screen, pluginApi.manifest)
    }

    function openBarSettings() {
        if (!pluginApi?.manifest?.entryPoints?.barWidgetSettings) {
            openPluginSettings()
            return
        }
        openSettingsEntry("barWidgetSettings")
    }

    readonly property string tooltipText: {
        switch (dictationState) {
        case "setup":
            return pluginApi?.tr("widget.setup") || "Installing dependencies..."
        case "recording":
            var recHint = pluginApi?.tr("widget.recordingHint") || "click bar mic to stop"
            if (root.stopHotkeyHint.length > 0)
                recHint += " · " + root.stopHotkeyHint
            return (pluginApi?.tr("widget.recording") || "Listening") + " — " + recHint
        case "transcribing":
            var stopHint = pluginApi?.tr("widget.recordingHint") || "click bar mic to stop"
            if (root.stopHotkeyHint.length > 0)
                stopHint += " · " + root.stopHotkeyHint
            return (pluginApi?.tr("widget.transcribing") || "Transcribing...")
                + " — " + stopHint
        case "starting":
            return pluginApi?.tr("widget.starting") || "Starting backend..."
        case "error":
            return (pluginApi?.tr("widget.error", {message: message}) || ("Error: " + message))
                + "\n" + (pluginApi?.tr("widget.errorHint") || "Click to retry — open settings for fix steps")
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
        running: root.dictationState === "recording" || root.dictationState === "starting" || root.dictationState === "transcribing"
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.pulse = 0
        NumberAnimation {
            from: 0; to: 1
            duration: root.dictationState === "recording" ? 600 : 900
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            from: 1; to: 0
            duration: root.dictationState === "recording" ? 600 : 900
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
            switch (root.dictationState) {
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
        border.color: root.dictationState === "recording"
            ? Color.mError
            : (root.dictationState === "error" ? Color.mError : Style.capsuleBorderColor)
        border.width: root.dictationState === "recording" ? 2 : Style.capsuleBorderWidth

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: {
                switch (root.dictationState) {
                case "recording": return Color.mError
                case "transcribing": return Color.mPrimary
                case "starting": return Color.mPrimary
                default: return "transparent"
                }
            }
            opacity: {
                switch (root.dictationState) {
                case "recording": return root.pulse * 0.25
                case "transcribing": return root.pulse * 0.12
                case "starting": return root.pulse * 0.18
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
                    switch (root.dictationState) {
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
                    switch (root.dictationState) {
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

                readonly property bool spinning: root.dictationState === "starting" || root.dictationState === "transcribing"
                property real spinAngle: 0
                rotation: spinning ? spinAngle : 0

                RotationAnimator on spinAngle {
                    running: iconItem.spinning
                    from: 0; to: 360
                    duration: 1000
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) iconItem.spinAngle = 0
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

        onEntered: TooltipService.show(root, root.tooltipText, BarService.getTooltipDirection(root.screenName))
        onExited: TooltipService.hide()

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                PanelService.showContextMenu(contextMenu, root, root.screen)
                return
            }
            if (root.mainInstance) {
                root.mainInstance.toggleRecording(root.screenName)
            }
        }
    }

    NPopupContextMenu {
        id: contextMenu

        model: [
            {
                "label": root.pluginApi?.tr("context.toggle") || "Toggle Dictation",
                "action": "toggle-dictation",
                "icon": "microphone"
            },
            {
                "label": root.pluginApi?.tr("context.openPanel") || "Open history panel",
                "action": "open-panel",
                "icon": "history"
            },
            {
                "label": (root.showOverlay
                    ? (root.pluginApi?.tr("context.overlayOn") || "Live overlay: on")
                    : (root.pluginApi?.tr("context.overlayOff") || "Live overlay: off")),
                "action": "toggle-overlay",
                "icon": root.showOverlay ? "eye" : "eye-off"
            },
            {
                "label": (root.autoType
                    ? (root.pluginApi?.tr("context.autoTypeOn") || "Auto-type: on")
                    : (root.pluginApi?.tr("context.autoTypeOff") || "Auto-type: off")),
                "action": "toggle-auto-type",
                "icon": "keyboard"
            },
            {
                "label": (root.vadEnabled
                    ? (root.isFwEngine
                        ? (root.pluginApi?.tr("context.vadOnFw") || "Silence detection: on")
                        : (root.pluginApi?.tr("context.vadOnSherpa") || root.pluginApi?.tr("context.vadOn") || "Noise gate (VAD): on"))
                    : (root.isFwEngine
                        ? (root.pluginApi?.tr("context.vadOffFw") || "Silence detection: off")
                        : (root.pluginApi?.tr("context.vadOffSherpa") || root.pluginApi?.tr("context.vadOff") || "Noise gate (VAD): off"))),
                "action": "toggle-vad",
                "icon": "filter"
            },
            {
                "label": root.pluginApi?.tr("context.barSettings") || "Bar quick settings",
                "action": "bar-settings",
                "icon": "adjustments"
            },
            {
                "label": root.pluginApi?.tr("context.pluginSettings") || "Plugin settings",
                "action": "plugin-settings",
                "icon": "settings"
            }
        ]

        onTriggered: action => {
            contextMenu.close()
            PanelService.closeContextMenu(screen)

            if (action === "toggle-dictation") {
                if (root.mainInstance) {
                    root.mainInstance.toggleRecording(root.screenName)
                }
            } else if (action === "open-panel") {
                root.pluginApi?.openPanel(screen, root)
            } else if (action === "toggle-overlay") {
                root.saveQuickSetting("showOverlay", !root.showOverlay)
            } else if (action === "toggle-auto-type") {
                root.saveQuickSetting("autoType", !root.autoType)
            } else if (action === "toggle-vad") {
                root.saveQuickSetting("vadEnabled", !root.vadEnabled)
            } else if (action === "bar-settings") {
                root.openBarSettings()
            } else if (action === "plugin-settings") {
                root.openPluginSettings()
            }
        }
    }

    Component.onCompleted: Logger.i("Dictation", "BarWidget loaded")
}
