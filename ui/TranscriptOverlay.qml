import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI
import qs.Widgets

PanelWindow {
    id: root

    required property ShellScreen screen
    property var pluginApi: null
    property var mainInstance: null

    readonly property bool showOverlay:
        pluginApi?.pluginSettings?.showOverlay ??
        pluginApi?.manifest?.metadata?.defaultSettings?.showOverlay ??
        true
    readonly property bool showPartialTranscript:
        pluginApi?.pluginSettings?.showPartialTranscript ??
        pluginApi?.manifest?.metadata?.defaultSettings?.showPartialTranscript ??
        true
    readonly property string overlayPosition:
        pluginApi?.pluginSettings?.overlayPosition ||
        pluginApi?.manifest?.metadata?.defaultSettings?.overlayPosition ||
        "bottom"
    readonly property string stopHotkeyHint:
        pluginApi?.pluginSettings?.stopHotkeyHint ||
        pluginApi?.manifest?.metadata?.defaultSettings?.stopHotkeyHint ||
        ""
    readonly property string screenPositionKey: screen?.name || "unknown"
    readonly property var savedOverlayPosition: {
        const positions = pluginApi?.pluginSettings?.overlayCustomPositions
        if (!positions || typeof positions !== "object")
            return null
        return positions[screenPositionKey] || null
    }
    readonly property string sessionState: mainInstance?.backendState || ""
    readonly property bool sessionActive: sessionState === "recording"
            || sessionState === "transcribing"
            || (sessionState === "starting" && (mainInstance?.pendingStart ?? false))
    readonly property bool active: sessionActive && showOverlay
    readonly property string committedText: mainInstance?.liveTranscript || ""
    readonly property string partialText: mainInstance?.partialTranscript || ""
    readonly property bool isRecording: sessionState === "recording"
    readonly property string statusText: {
        if (sessionState === "recording")
            return pluginApi?.tr("overlay.listening") || "Listening..."
        if (sessionState === "starting")
            return pluginApi?.tr("overlay.starting") || "Starting..."
        return pluginApi?.tr("overlay.finishing") || "Finishing..."
    }
    readonly property int shadowPadding: Style.shadowBlurMax + Style.marginL
    readonly property int barOffsetBottom: {
        if (overlayPosition !== "bottom")
            return Style.marginXL
        const barPos = Settings.getBarPositionForScreen(screen?.name || "")
        if (barPos !== "bottom")
            return Style.marginXL
        const isFloating = Settings.data.bar.barType === "floating"
        const floatMarginV = isFloating ? Math.ceil(Settings.data.bar.marginVertical) : 0
        return Style.getBarHeightForScreen(screen?.name || "") + floatMarginV + Style.marginXL
    }
    readonly property int barOffsetTop: {
        if (overlayPosition !== "top")
            return Style.marginXL
        const barPos = Settings.getBarPositionForScreen(screen?.name || "")
        if (barPos !== "top")
            return Style.marginXL
        const isFloating = Settings.data.bar.barType === "floating"
        const floatMarginV = isFloating ? Math.ceil(Settings.data.bar.marginVertical) : 0
        return Style.getBarHeightForScreen(screen?.name || "") + floatMarginV + Style.marginXL
    }

    property bool positionDraggedThisSession: false
    property bool _positionPresetReactive: false

    onPluginApiChanged: {
        if (pluginApi)
            restoreOverlayPositionFromSettings()
    }

    onOverlayPositionChanged: {
        if (!_positionPresetReactive)
            return
        resetLayoutForPositionPreset()
    }

    onActiveChanged: {
        if (!active)
            positionDraggedThisSession = false
    }

    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    visible: active
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "noctalia-dictation-overlay-" + (screen?.name || "unknown")
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    function clampOverlayX(x) {
        const maxX = Math.max(0, root.width - cardContainer.width)
        return Math.max(0, Math.min(x, maxX))
    }

    function clampOverlayY(y) {
        const maxY = Math.max(0, root.height - cardContainer.height)
        return Math.max(0, Math.min(y, maxY))
    }

    function detachCardFromAnchors() {
        if (cardContainer.useCustomAnchors)
            return
        const pos = cardContainer.mapToItem(root, 0, 0)
        cardContainer.useCustomAnchors = true
        cardContainer.x = clampOverlayX(pos.x)
        cardContainer.y = clampOverlayY(pos.y)
    }

    function applySavedOverlayPosition() {
        const pos = savedOverlayPosition
        if (!pos || pos.x < 0 || pos.y < 0)
            return
        cardContainer.useCustomAnchors = true
        cardContainer.x = clampOverlayX(pos.x)
        cardContainer.y = clampOverlayY(pos.y)
    }

    function restoreOverlayPositionFromSettings() {
        applySavedOverlayPosition()
        Qt.callLater(() => { _positionPresetReactive = true })
    }

    function saveOverlayPosition() {
        if (!pluginApi || !cardContainer.useCustomAnchors)
            return
        const positions = Object.assign({}, pluginApi.pluginSettings?.overlayCustomPositions || {})
        positions[screenPositionKey] = {
            x: Math.round(cardContainer.x),
            y: Math.round(cardContainer.y)
        }
        pluginApi.pluginSettings.overlayCustomPositions = positions
        pluginApi.saveSettings()
    }

    function clearSavedOverlayPosition() {
        if (!pluginApi)
            return
        const positions = Object.assign({}, pluginApi.pluginSettings?.overlayCustomPositions || {})
        if (!(screenPositionKey in positions))
            return
        delete positions[screenPositionKey]
        pluginApi.pluginSettings.overlayCustomPositions = positions
        pluginApi.saveSettings()
    }

    function resetLayoutForPositionPreset() {
        if (positionDraggedThisSession)
            return
        cardContainer.useCustomAnchors = false
        clearSavedOverlayPosition()
    }

    Item {
        id: cardContainer
        property bool useCustomAnchors: false

        anchors.horizontalCenter: useCustomAnchors ? undefined : parent.horizontalCenter
        anchors.bottom: !useCustomAnchors && overlayPosition === "bottom" ? parent.bottom : undefined
        anchors.top: !useCustomAnchors && overlayPosition === "top" ? parent.top : undefined
        anchors.bottomMargin: !useCustomAnchors && overlayPosition === "bottom" ? root.barOffsetBottom : 0
        anchors.topMargin: !useCustomAnchors && overlayPosition === "top" ? root.barOffsetTop : 0
        width: cardBackground.width + root.shadowPadding * 2
        height: cardBackground.height + root.shadowPadding * 2
        opacity: root.active ? 1 : 0

        Component.onCompleted: {
            if (pluginApi)
                restoreOverlayPositionFromSettings()
        }

        Behavior on opacity {
            NumberAnimation { duration: Style.animationFast }
        }

        Rectangle {
            id: cardBackground
            anchors.centerIn: parent
            width: Math.min(root.width * 0.7, 720 * Style.uiScaleRatio)
            implicitHeight: contentColumn.implicitHeight + Style.marginL * 2
            radius: Style.radiusL
            color: Qt.alpha(Color.mSurface, Style.effectivePanelOpacity)
            border.color: Qt.alpha(Color.mOutline, Style.effectivePanelOpacity)
            border.width: Style.borderS

            ColumnLayout {
                id: contentColumn
                anchors {
                    fill: parent
                    margins: Style.marginL
                }
                spacing: Style.marginS

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    NIcon {
                        icon: root.isRecording ? "player-record-filled" : "loader"
                        color: root.isRecording ? Color.mError : Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeS
                        applyUiScale: false

                        SequentialAnimation on opacity {
                            running: root.isRecording
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.35; duration: 500; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 0.35; to: 1; duration: 500; easing.type: Easing.InOutQuad }
                        }

                        RotationAnimator on rotation {
                            running: !root.isRecording
                            from: 0; to: 360
                            duration: 1000
                            loops: Animation.Infinite
                        }
                    }

                    NText {
                        text: root.statusText
                        color: Color.mOnSurface
                        pointSize: Style.fontSizeS
                        font.weight: Style.fontWeightBold
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: Style.marginM

                        NIcon {
                            anchors.centerIn: parent
                            icon: "grip-vertical"
                            color: Color.mOnSurfaceVariant
                            pointSize: Style.fontSizeXS
                            opacity: 0.55
                            applyUiScale: false
                        }

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.SizeAllCursor
                            property point dragStart
                            property point cardStart

                            onEntered: TooltipService.show(
                                dragArea,
                                pluginApi?.tr("overlay.dragHint") || "Drag to reposition",
                                BarService.getTooltipDirection(screen?.name || ""))
                            onExited: TooltipService.hide()

                            onPressed: mouse => {
                                root.positionDraggedThisSession = true
                                root.detachCardFromAnchors()
                                dragStart = mapToItem(root, mouse.x, mouse.y)
                                cardStart = Qt.point(cardContainer.x, cardContainer.y)
                            }

                            onPositionChanged: mouse => {
                                if (!pressed)
                                    return
                                const current = mapToItem(root, mouse.x, mouse.y)
                                cardContainer.x = root.clampOverlayX(cardStart.x + current.x - dragStart.x)
                                cardContainer.y = root.clampOverlayY(cardStart.y + current.y - dragStart.y)
                            }

                            onReleased: root.saveOverlayPosition()
                        }
                    }

                    NText {
                        visible: root.stopHotkeyHint.length > 0
                        text: root.stopHotkeyHint
                        color: Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeXS
                        Layout.alignment: Qt.AlignVCenter
                        Layout.maximumWidth: cardBackground.width * 0.3
                        elide: Text.ElideRight
                    }

                    NIconButton {
                        icon: "player-stop"
                        Layout.preferredWidth: Style.iconSizeM
                        Layout.preferredHeight: Style.iconSizeM
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: Style.marginXS
                        tooltipText: (pluginApi?.tr("overlay.stop") || "Stop dictation")
                            + (root.stopHotkeyHint.length > 0 ? (" (" + root.stopHotkeyHint + ")") : "")
                        onClicked: {
                            if (mainInstance) {
                                mainInstance.stopRecording()
                            }
                        }
                    }
                }

                NText {
                    Layout.fillWidth: true
                    visible: root.committedText.length > 0
                    text: root.committedText
                    color: Color.mOnSurface
                    pointSize: Style.fontSizeM
                    wrapMode: Text.WordWrap
                    maximumLineCount: 6
                    elide: Text.ElideRight
                }

                NText {
                    Layout.fillWidth: true
                    visible: showPartialTranscript && root.partialText.length > 0
                    text: root.partialText
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeM
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    font.italic: true
                }

                NText {
                    Layout.fillWidth: true
                    visible: root.committedText.length === 0 && root.partialText.length === 0
                    text: pluginApi?.tr("overlay.waiting") || "Waiting for speech..."
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeM
                    font.italic: true
                    opacity: 0.7
                }
            }
        }

        NDropShadow {
            anchors.fill: cardBackground
            source: cardBackground
            autoPaddingEnabled: true
        }
    }
}
