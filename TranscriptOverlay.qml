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

    readonly property bool active: mainInstance?.backendState === "recording"
            || mainInstance?.backendState === "transcribing"
    readonly property string committedText: mainInstance?.liveTranscript || ""
    readonly property string partialText: mainInstance?.partialTranscript || ""
    readonly property bool isRecording: mainInstance?.backendState === "recording"
    readonly property int shadowPadding: Style.shadowBlurMax + Style.marginL
    readonly property int barOffsetBottom: {
        const barPos = Settings.getBarPositionForScreen(screen?.name || "")
        if (barPos !== "bottom")
            return Style.marginXL
        const isFloating = Settings.data.bar.barType === "floating"
        const floatMarginV = isFloating ? Math.ceil(Settings.data.bar.marginVertical) : 0
        return Style.getBarHeightForScreen(screen?.name || "") + floatMarginV + Style.marginXL
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

    Item {
        id: cardContainer
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.barOffsetBottom
        width: cardBackground.width + root.shadowPadding * 2
        height: cardBackground.height + root.shadowPadding * 2
        opacity: root.active ? 1 : 0

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
                        text: root.isRecording
                            ? (pluginApi?.tr("overlay.listening") || "Listening...")
                            : (pluginApi?.tr("overlay.finishing") || "Finishing...")
                        color: Color.mOnSurface
                        pointSize: Style.fontSizeS
                        font.weight: Style.fontWeightBold
                    }

                    Item { Layout.fillWidth: true }

                    NText {
                        text: pluginApi?.tr("overlay.hint") || "Hotkey or click mic to stop"
                        color: Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeXS
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
                    visible: root.partialText.length > 0
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
