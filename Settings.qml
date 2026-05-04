import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null

  readonly property var geometryPlaceholder: settingsContainer
  readonly property bool allowAttach: true

  property real contentPreferredWidth: 700 * Style.uiScaleRatio
  property real contentPreferredHeight: 600 * Style.uiScaleRatio

  anchors.fill: parent

  readonly property var _modelKeys: ["tiny", "base", "small", "medium", "large-v3"]
  readonly property var _languageKeys: ["auto", "en", "es", "fr", "de", "it", "pt", "nl", "pl", "ru", "zh", "ja", "ko", "ar", "hi", "tr", "vi", "th", "id", "uk"]
  readonly property var _deviceKeys: ["auto", "cpu", "cuda"]
  readonly property var _computeTypeKeys: ["int8", "float16", "float32"]

  function saveSettings() {
    if (!pluginApi) return
    pluginApi.pluginSettings.model = root.editModel
    pluginApi.pluginSettings.language = root.editLanguage
    pluginApi.pluginSettings.device = root.editDevice
    pluginApi.pluginSettings.computeType = root.editComputeType
    pluginApi.pluginSettings.vadEnabled = root.editVad
    pluginApi.pluginSettings.recordingTimeout = root.editTimeout
    pluginApi.saveSettings()
  }

  readonly property var _defaults: pluginApi?.manifest?.metadata?.defaultSettings

  property string editModel:
    pluginApi?.pluginSettings?.model ||
    _defaults?.model ||
    "base"

  property string editLanguage:
    pluginApi?.pluginSettings?.language ||
    _defaults?.language ||
    "auto"

  property string editDevice:
    pluginApi?.pluginSettings?.device ||
    _defaults?.device ||
    "auto"

  property string editComputeType:
    pluginApi?.pluginSettings?.computeType ||
    _defaults?.computeType ||
    "int8"

  property bool editVad:
    pluginApi?.pluginSettings?.vadEnabled ??
    _defaults?.vadEnabled ??
    true

  property int editTimeout:
    pluginApi?.pluginSettings?.recordingTimeout ||
    _defaults?.recordingTimeout ||
    30

  Rectangle {
    id: settingsContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors {
        fill: parent
        margins: Style.marginL
      }
      spacing: Style.marginM

      NText {
        text: pluginApi?.tr("settings.title") || "Dictation Settings"
        pointSize: Style.fontSizeXL
        font.weight: Font.Bold
        color: Color.mOnSurface
      }

      Rectangle {
        Layout.fillWidth: true
        height: backendStatusRow.implicitHeight + Style.marginM * 2
        color: {
          var st = pluginApi?.mainInstance?.backendState || "stopped"
          if (st === "error") return Color.mErrorContainer
          if (st === "idle" || st === "recording" || st === "transcribing") return Color.mPrimaryContainer
          if (st === "starting" || st === "setup" || st === "stopping") return Color.mSecondaryContainer
          return Color.mSurfaceVariant
        }
        radius: Style.radiusM

        RowLayout {
          id: backendStatusRow
          anchors {
            fill: parent
            margins: Style.marginM
          }
          spacing: Style.marginM

          NText {
            text: pluginApi?.tr("settings.backendStatus") || "Backend:"
            color: Color.mOnSurface
            font.weight: Font.Medium
          }
          NText {
            text: {
              var st = pluginApi?.mainInstance?.backendState || "stopped"
              switch (st) {
                case "idle": return "Running"
                case "recording": return "Recording"
                case "transcribing": return "Transcribing"
                case "starting": return "Starting..."
                case "stopping": return "Stopping..."
                case "setup": return "Installing..."
                case "error": return "Error"
                default: return "Stopped"
              }
            }
            color: Color.mOnSurface
          }
          NText {
            text: pluginApi?.mainInstance?.backendMessage || ""
            color: Color.mOnSurfaceVariant
            visible: text.length > 0
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
          Item { Layout.fillWidth: true }

          NButton {
            text: pluginApi?.tr("settings.restartBackend") || "Restart"
            outlined: true
            visible: {
              var st = pluginApi?.mainInstance?.backendState || "stopped"
              return st === "idle" || st === "error"
            }
            Timer {
              id: restartDelayTimer
              interval: 500
              onTriggered: {
                if (pluginApi?.mainInstance) {
                  pluginApi.mainInstance.ensureBackend()
                }
              }
            }
            onClicked: {
              if (pluginApi?.mainInstance) {
                var mi = pluginApi.mainInstance
                Quickshell.execDetached(mi.pythonCmd(["exit"]))
                mi.backendState = "stopping"
                mi._venvReady = true
                restartDelayTimer.restart()
              }
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurfaceVariant
        radius: Style.radiusL

        NScrollView {
          anchors.fill: parent

          ColumnLayout {
            anchors {
              fill: parent
              margins: Style.marginL
            }
            spacing: Style.marginM

            NText {
              text: pluginApi?.tr("settings.model") || "Whisper model"
              pointSize: Style.fontSizeM
              font.weight: Font.Medium
              color: Color.mOnSurface
            }
            NText {
              text: pluginApi?.tr("settings.modelDesc") || "Larger models are more accurate but slower"
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
            NComboBox {
              Layout.fillWidth: true
              model: ["Tiny", "Base", "Small", "Medium", "Large v3"]
              currentIndex: root._modelKeys.indexOf(root.editModel)
              onCurrentIndexChanged: {
                if (currentIndex >= 0 && currentIndex < root._modelKeys.length) {
                  root.editModel = root._modelKeys[currentIndex]
                }
              }
            }

            Item { height: Style.marginM }

            NText {
              text: pluginApi?.tr("settings.language") || "Language"
              pointSize: Style.fontSizeM
              font.weight: Font.Medium
              color: Color.mOnSurface
            }
            NText {
              text: pluginApi?.tr("settings.languageDesc") || "Auto-detect or pick a specific language"
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
            NComboBox {
              Layout.fillWidth: true
              model: ["Auto-detect", "English", "Spanish", "French", "German", "Italian", "Portuguese", "Dutch", "Polish", "Russian", "Chinese", "Japanese", "Korean", "Arabic", "Hindi", "Turkish", "Vietnamese", "Thai", "Indonesian", "Ukrainian"]
              currentIndex: root._languageKeys.indexOf(root.editLanguage)
              onCurrentIndexChanged: {
                if (currentIndex >= 0 && currentIndex < root._languageKeys.length) {
                  root.editLanguage = root._languageKeys[currentIndex]
                }
              }
            }

            Item { height: Style.marginM }

            NText {
              text: pluginApi?.tr("settings.device") || "Compute device"
              pointSize: Style.fontSizeM
              font.weight: Font.Medium
              color: Color.mOnSurface
            }
            NText {
              text: pluginApi?.tr("settings.deviceDesc") || "Auto picks CUDA if available"
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
            NComboBox {
              Layout.fillWidth: true
              model: ["Auto", "CPU", "CUDA"]
              currentIndex: root._deviceKeys.indexOf(root.editDevice)
              onCurrentIndexChanged: {
                if (currentIndex >= 0 && currentIndex < root._deviceKeys.length) {
                  root.editDevice = root._deviceKeys[currentIndex]
                }
              }
            }

            Item { height: Style.marginM }

            NText {
              text: pluginApi?.tr("settings.computeType") || "Compute type"
              pointSize: Style.fontSizeM
              font.weight: Font.Medium
              color: Color.mOnSurface
            }
            NText {
              text: pluginApi?.tr("settings.computeTypeDesc") || "int8 is fastest on CPU, float16 for GPU"
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
            NComboBox {
              Layout.fillWidth: true
              model: ["INT8", "Float 16", "Float 32"]
              currentIndex: root._computeTypeKeys.indexOf(root.editComputeType)
              onCurrentIndexChanged: {
                if (currentIndex >= 0 && currentIndex < root._computeTypeKeys.length) {
                  root.editComputeType = root._computeTypeKeys[currentIndex]
                }
              }
            }

            Item { height: Style.marginM }

            NText {
              text: pluginApi?.tr("settings.vad") || "Voice activity detection"
              pointSize: Style.fontSizeM
              font.weight: Font.Medium
              color: Color.mOnSurface
            }
            NText {
              text: pluginApi?.tr("settings.vadDesc") || "Automatically stop recording during silence"
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
            RowLayout {
              Layout.fillWidth: true
              NText {
                text: root.editVad ? "Enabled" : "Disabled"
                color: Color.mOnSurface
              }
              Item { Layout.fillWidth: true }
              Switch {
                checked: root.editVad
                onCheckedChanged: root.editVad = checked
              }
            }

            Item { height: Style.marginM }

            NText {
              text: pluginApi?.tr("settings.timeout") || "Recording timeout"
              pointSize: Style.fontSizeM
              font.weight: Font.Medium
              color: Color.mOnSurface
            }
            NText {
              text: pluginApi?.tr("settings.timeoutDesc") || "Maximum seconds to record before auto-stop"
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
            NTextInput {
              Layout.fillWidth: true
              text: String(root.editTimeout)
              onTextChanged: {
                var val = parseInt(text, 10)
                if (!isNaN(val) && val > 0) {
                  root.editTimeout = val
                }
              }
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM
        Item { Layout.fillWidth: true }

        NButton {
          text: "Cancel"
          outlined: true
          onClicked: {
            var defs = pluginApi?.manifest?.metadata?.defaultSettings
            root.editModel = pluginApi?.pluginSettings?.model || defs?.model || "base"
            root.editLanguage = pluginApi?.pluginSettings?.language || defs?.language || "auto"
            root.editDevice = pluginApi?.pluginSettings?.device || defs?.device || "auto"
            root.editComputeType = pluginApi?.pluginSettings?.computeType || defs?.computeType || "int8"
            root.editVad = pluginApi?.pluginSettings?.vadEnabled ?? defs?.vadEnabled ?? true
            root.editTimeout = pluginApi?.pluginSettings?.recordingTimeout || defs?.recordingTimeout || 30
          }
        }

        NButton {
          text: "Save & Apply"
          onClicked: {
            root.saveSettings()
            if (pluginApi?.mainInstance) {
              pluginApi.mainInstance.updateSettings()
            }
            ToastService.showNotice("Settings saved")
          }
        }
      }
    }
  }
}
