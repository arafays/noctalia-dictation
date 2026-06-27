pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI
import qs.Widgets

PanelWindow {
    id: root

    required property ShellScreen shellScreen
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
    readonly property string screenPositionKey: shellScreen?.name || "unknown"
    readonly property var savedOverlayPosition: {
        const positions = pluginApi?.pluginSettings?.overlayCustomPositions
        if (!positions || typeof positions !== "object")
            return null
        return positions[screenPositionKey] || null
    }
    readonly property int positionRevision: mainInstance ? mainInstance.overlayPositionRevision : 0
    readonly property bool positionPreview: mainInstance ? mainInstance.overlayPositionPreview : false
    readonly property string sessionState: mainInstance ? mainInstance.backendState : ""
    readonly property bool sessionActive: sessionState === "recording"
            || sessionState === "transcribing"
            || (sessionState === "starting" && mainInstance && mainInstance.pendingStart)
    readonly property bool sessionVisible: sessionActive && showOverlay
    readonly property bool screenMatches: {
        if (!mainInstance)
            return false
        const target = mainInstance.overlayScreenName || ""
        if (target.length === 0)
            return false
        return (shellScreen?.name || "") === target
    }
    readonly property bool active: (sessionVisible || positionPreview) && screenMatches
    readonly property bool dragEnabled: positionPreview && !sessionActive
    readonly property string committedText: positionPreview
        ? (pluginApi?.tr("overlay.previewCommitted") || "Committed text shows here.")
        : (mainInstance ? mainInstance.liveTranscript : "")
    readonly property string partialText: positionPreview && showPartialTranscript
        ? (pluginApi?.tr("overlay.previewPartial") || "Partial preview...")
        : (mainInstance ? mainInstance.partialTranscript : "")
    readonly property bool isRecording: !positionPreview && sessionState === "recording"
    readonly property bool hasTranscript: committedText.length > 0 || partialText.length > 0
    readonly property string statusText: {
        if (positionPreview)
            return pluginApi?.tr("overlay.adjustPosition") || "Adjust position"
        if (sessionState === "recording")
            return pluginApi?.tr("overlay.listening") || "Listening"
        if (sessionState === "starting")
            return pluginApi?.tr("overlay.starting") || "Starting"
        return pluginApi?.tr("overlay.finishing") || "Finishing"
    }
    readonly property int bubbleMaxWidth: Math.min(root.width * 0.42, 360 * Style.uiScaleRatio)
    readonly property real bubbleOpacity: positionPreview ? 0.92 : 0.82

    property bool _positionReady: false
    property bool _dragging: false

    on_DraggingChanged: Qt.callLater(refreshClickMask)

    function refreshClickMask() {
        if (maskLoader.item)
            maskLoader.item.changed()
    }

    function bubbleContainsRootPoint(rootX, rootY) {
        return rootX >= bubble.x && rootX <= bubble.x + bubble.width
            && rootY >= bubble.y && rootY <= bubble.y + bubble.height
    }

    onDragEnabledChanged: Qt.callLater(refreshClickMask)

    onPluginApiChanged: {
        if (pluginApi)
            restoreOverlayPosition()
    }

    onPositionRevisionChanged: restoreOverlayPosition()

    onPositionPreviewChanged: {
        if (positionPreview) {
            Qt.callLater(ensureOverlayPosition)
        } else {
            _dragging = false
        }
        Qt.callLater(refreshClickMask)
    }

    onSavedOverlayPositionChanged: {
        if (_dragging)
            return
        _positionReady = false
        if (active)
            Qt.callLater(ensureOverlayPosition)
    }

    onActiveChanged: {
        if (active) {
            Qt.callLater(ensureOverlayPosition)
        } else {
            if (pluginApi && (_positionReady || _dragging))
                writeOverlayPosition()
            _dragging = false
            _positionReady = false
        }
        Qt.callLater(refreshClickMask)
    }

    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    visible: active
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "noctalia-dictation-overlay-" + (shellScreen?.name || "unknown")
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    function clampOverlayX(x) {
        const maxX = Math.max(0, root.width - bubble.width)
        return Math.max(0, Math.min(x, maxX))
    }

    function clampOverlayY(y) {
        const maxY = Math.max(0, root.height - bubble.height)
        return Math.max(0, Math.min(y, maxY))
    }

    function bottomBarOffset() {
        const margin = Style.marginL
        const barPos = Settings.getBarPositionForScreen(shellScreen?.name || "")
        if (barPos !== "bottom")
            return margin
        const isFloating = Settings.data.bar.barType === "floating"
        const floatMarginV = isFloating ? Math.ceil(Settings.data.bar.marginVertical) : 0
        return Style.getBarHeightForScreen(shellScreen?.name || "") + floatMarginV + margin * 2
    }

    function applySavedOverlayPosition() {
        const pos = savedOverlayPosition
        if (!pos || pos.x < 0 || pos.y < 0)
            return false
        bubble.x = clampOverlayX(pos.x)
        bubble.y = clampOverlayY(pos.y)
        return true
    }

    function placeDefaultOverlayPosition() {
        bubble.x = clampOverlayX((root.width - bubble.width) / 2)
        bubble.y = clampOverlayY(root.height - bubble.height - bottomBarOffset())
    }

    function ensureOverlayPosition() {
        if (_positionReady)
            return
        if (!applySavedOverlayPosition())
            placeDefaultOverlayPosition()
        _positionReady = true
        refreshClickMask()
    }

    function restoreOverlayPosition() {
        if (_dragging)
            return
        _positionReady = false
        if (active)
            ensureOverlayPosition()
    }

    function saveOverlayPosition() {
        if (!pluginApi || !dragEnabled)
            return
        writeOverlayPosition()
        _positionReady = true
    }

    function writeOverlayPosition() {
        if (!pluginApi)
            return
        const positions = Object.assign({}, pluginApi.pluginSettings?.overlayCustomPositions || {})
        positions[screenPositionKey] = {
            x: Math.round(bubble.x),
            y: Math.round(bubble.y)
        }
        pluginApi.pluginSettings.overlayCustomPositions = positions
        pluginApi.saveSettings()
    }

    Item {
        id: bubble
        opacity: root.active ? 1 : 0
        width: bubbleBackground.width
        height: bubbleBackground.height

        onWidthChanged: if (root.dragEnabled && !root._dragging) Qt.callLater(root.refreshClickMask)
        onHeightChanged: if (root.dragEnabled && !root._dragging) Qt.callLater(root.refreshClickMask)

        Behavior on opacity {
            NumberAnimation { duration: Style.animationFast }
        }

        Behavior on width {
            enabled: !root._dragging
            NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic }
        }

        Behavior on height {
            enabled: !root._dragging
            NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: bubbleBackground
            width: Math.min(root.bubbleMaxWidth, contentColumn.implicitWidth + Style.marginM * 2)
            implicitHeight: contentColumn.implicitHeight + Style.marginS * 2
            radius: Math.min(Style.radiusXL, height / 2)
            color: Qt.alpha(Color.mSurface, root.bubbleOpacity)
            border.color: root.positionPreview
                ? Qt.alpha(Color.mPrimary, 0.55)
                : Qt.alpha(Color.mOutline, 0.28)
            border.width: root.positionPreview ? 2 : Style.borderS

            ColumnLayout {
                id: contentColumn
                anchors {
                    fill: parent
                    margins: Style.marginS
                }
                spacing: Style.marginXS

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginXS

                    Rectangle {
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        Layout.alignment: Qt.AlignVCenter
                        radius: 4
                        color: root.isRecording ? Color.mError : Color.mOnSurfaceVariant
                        opacity: root.isRecording ? 1 : 0.65

                        SequentialAnimation on opacity {
                            running: root.isRecording
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.35; duration: 550; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 0.35; to: 1; duration: 550; easing.type: Easing.InOutQuad }
                        }
                    }

                    NText {
                        text: root.statusText
                        color: Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeXS
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                NText {
                    Layout.fillWidth: true
                    visible: root.committedText.length > 0
                    text: root.committedText
                    color: Color.mOnSurface
                    pointSize: Style.fontSizeXS
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.italic: root.positionPreview
                }

                NText {
                    Layout.fillWidth: true
                    visible: root.showPartialTranscript && root.partialText.length > 0
                    text: root.partialText
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeXS
                    wrapMode: Text.WordWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    font.italic: true
                    opacity: 0.88
                }

                NText {
                    Layout.fillWidth: true
                    visible: !root.hasTranscript && !root.positionPreview
                    text: root.pluginApi?.tr("overlay.waiting") || "Waiting for speech..."
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeXS
                    font.italic: true
                    opacity: 0.55
                }
            }
        }
    }

    // Full-screen hit target used only while dragging so the Wayland input
    // region is not stuck at the bubble's pre-drag position.
    Item {
        id: dragHitLayer
        anchors.fill: parent
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: root.dragEnabled
        hoverEnabled: root.dragEnabled
        cursorShape: root.dragEnabled && root.bubbleContainsRootPoint(mouseX, mouseY)
            ? Qt.SizeAllCursor : Qt.ArrowCursor
        preventStealing: true
        z: 1
        property point dragStart
        property point bubbleStart

        onEntered: {
            if (root.bubbleContainsRootPoint(mouseX, mouseY)) {
                TooltipService.show(
                    dragArea,
                    root.pluginApi?.tr("overlay.dragHint") || "Drag to move",
                    BarService.getTooltipDirection(root.shellScreen?.name || ""))
            }
        }
        onExited: TooltipService.hide()

        onPressed: mouse => {
            if (!root.bubbleContainsRootPoint(mouse.x, mouse.y))
                return
            root._dragging = true
            root.ensureOverlayPosition()
            dragStart = Qt.point(mouse.x, mouse.y)
            bubbleStart = Qt.point(bubble.x, bubble.y)
            Qt.callLater(root.refreshClickMask)
        }

        onPositionChanged: mouse => {
            if (!pressed || !root._dragging)
                return
            bubble.x = root.clampOverlayX(bubbleStart.x + mouse.x - dragStart.x)
            bubble.y = root.clampOverlayY(bubbleStart.y + mouse.y - dragStart.y)
        }

        onReleased: {
            if (!root._dragging)
                return
            root.saveOverlayPosition()
            root._dragging = false
            Qt.callLater(root.refreshClickMask)
        }

        onCanceled: {
            root._dragging = false
            Qt.callLater(root.refreshClickMask)
        }
    }

    Component {
        id: passThroughMaskComponent
        Region {}
    }

    Component {
        id: bubbleDragMaskComponent
        Region { item: bubble }
    }

    Component {
        id: fullWindowDragMaskComponent
        Region { item: dragHitLayer }
    }

    Loader {
        id: maskLoader
        active: true
        sourceComponent: !root.dragEnabled ? passThroughMaskComponent
            : (root._dragging ? fullWindowDragMaskComponent : bubbleDragMaskComponent)
        onLoaded: root.refreshClickMask()
    }

    mask: maskLoader.item
}
