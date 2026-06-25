import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  spacing: Style.marginM

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NIcon {
      icon: "microphone"
      pointSize: Style.fontSizeXL
      color: Color.mPrimary
    }

    NText {
      text: pluginApi?.tr("settings.title") || "Dictation Settings"
      pointSize: Style.fontSizeL
      font.weight: Font.Medium
      color: Color.mOnSurface
    }

    Item { Layout.fillWidth: true }
  }

  NDivider {
    Layout.fillWidth: true
  }

  readonly property var _languageKeys: ["auto", "en", "es", "fr", "de", "it", "pt", "nl", "pl", "ru", "zh", "ja", "ko", "ar", "hi", "tr", "vi", "th", "id", "uk"]

  readonly property var _engineKeys: ["auto", "sherpa"]
  readonly property var _sherpaProfileKeys: ["auto", "english", "multilingual"]
  readonly property var _sherpaProviderKeys: ["auto", "cpu", "cuda"]

  readonly property var _defaults: pluginApi?.manifest?.metadata?.defaultSettings

  property string editEngine:
    pluginApi?.pluginSettings?.engine ||
    _defaults?.engine ||
    "auto"

  property string editSherpaProfile:
    pluginApi?.pluginSettings?.sherpaProfile ||
    _defaults?.sherpaProfile ||
    "auto"

  property string editSherpaProvider:
    pluginApi?.pluginSettings?.sherpaProvider ||
    _defaults?.sherpaProvider ||
    "auto"

  property string editLanguage:
    pluginApi?.pluginSettings?.language ||
    _defaults?.language ||
    "auto"

  property int editTimeout:
    pluginApi?.pluginSettings?.recordingTimeout ??
    _defaults?.recordingTimeout ??
    0

  // Backend status indicator
  Rectangle {
    Layout.fillWidth: true
    height: backendStatusRow.implicitHeight + Style.marginM * 2
    color: {
      var st = pluginApi?.mainInstance?.backendState || "stopped"
      switch (st) {
      case "error": return Color.mErrorContainer
      case "idle": return Color.mPrimaryContainer
      case "recording": return Color.mErrorContainer
      case "transcribing": return Color.mPrimaryContainer
      case "starting": return Color.mSecondaryContainer
      case "setup": return Color.mSecondaryContainer
      default: return Color.mSurfaceVariant
      }
    }
    radius: Style.radiusM

    RowLayout {
      id: backendStatusRow
      anchors {
        fill: parent
        margins: Style.marginM
      }
      spacing: Style.marginS

      NIcon {
        id: statusIcon
        icon: {
          var st = pluginApi?.mainInstance?.backendState || "stopped"
          switch (st) {
          case "idle": return "circle-check-filled"
          case "recording": return "player-record-filled"
          case "transcribing": return "loader"
          case "starting": return "loader"
          case "stopping": return "player-stop"
          case "setup": return "download"
          case "error": return "alert-triangle-filled"
          default: return "circle-off"
          }
        }
        color: {
          var st = pluginApi?.mainInstance?.backendState || "stopped"
          switch (st) {
          case "idle": return Color.mOnPrimaryContainer
          case "recording": return Color.mOnErrorContainer
          case "transcribing": return Color.mOnPrimaryContainer
          case "starting": return Color.mOnSecondaryContainer
          case "stopping": return Color.mOnSecondaryContainer
          case "setup": return Color.mOnSecondaryContainer
          case "error": return Color.mOnErrorContainer
          default: return Color.mOnSurfaceVariant
          }
        }
        applyUiScale: false

        RotationAnimator on rotation {
          running: {
            var st = pluginApi?.mainInstance?.backendState || "stopped"
            return st === "starting" || st === "transcribing"
          }
          from: 0; to: 360
          duration: 1000
          loops: Animation.Infinite
        }
        Binding {
          target: statusIcon
          property: "rotation"
          value: 0
          when: {
            var st = pluginApi?.mainInstance?.backendState || "stopped"
            return st !== "starting" && st !== "transcribing"
          }
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        NText {
          text: pluginApi?.tr("settings.backendStatus") || "Backend:"
          color: Color.mOnSurface
          font.weight: Font.Medium
        }
        NText {
          text: {
            var st = pluginApi?.mainInstance?.backendState || "stopped"
            switch (st) {
              case "idle": return pluginApi?.tr("settings.status.idle") || "Ready"
              case "recording": return pluginApi?.tr("settings.status.recording") || "Recording"
              case "transcribing": return pluginApi?.tr("settings.status.transcribing") || "Transcribing"
              case "starting": return pluginApi?.tr("settings.status.starting") || "Starting..."
              case "stopping": return pluginApi?.tr("settings.status.stopping") || "Stopping..."
              case "setup": return pluginApi?.tr("settings.status.setup") || "Installing..."
              case "error": return pluginApi?.tr("settings.status.error") || "Error"
              default: return pluginApi?.tr("settings.status.stopped") || "Stopped"
            }
          }
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeS
        }
        NText {
          text: pluginApi?.mainInstance?.backendMessage || ""
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeXS
          visible: text.length > 0
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      Item { Layout.fillWidth: true }

      NButton {
        text: pluginApi?.tr("settings.restartBackend") || "Restart"
        outlined: true
        visible: {
          var st = pluginApi?.mainInstance?.backendState || "stopped"
          return st === "idle" || st === "error"
        }
        onClicked: {
          if (pluginApi?.mainInstance) {
            pluginApi.mainInstance.restartBackend()
          }
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  NLabel {
    label: pluginApi?.tr("settings.engine") || "Speech engine"
    description: pluginApi?.tr("settings.engineDesc") || "sherpa-onnx two-pass streaming with Silero VAD noise gating (Zipformer live + Whisper/SenseVoice finals)."
  }

  NComboBox {
    Layout.fillWidth: true
    model: ["Auto (recommended)", "sherpa-onnx two-pass"]
    currentIndex: Math.max(0, root._engineKeys.indexOf(root.editEngine))
    onCurrentIndexChanged: {
      if (currentIndex >= 0 && currentIndex < root._engineKeys.length) {
        root.editEngine = root._engineKeys[currentIndex]
      }
    }
  }

  NLabel {
    label: pluginApi?.tr("settings.sherpaProfile") || "sherpa model profile"
    description: pluginApi?.tr("settings.sherpaProfileDesc") || "English uses Zipformer+Whisper. Multilingual adds SenseVoice for better non-English accuracy."
    Layout.topMargin: Style.marginS
  }

  NComboBox {
    Layout.fillWidth: true
    model: ["Auto from language", "English", "Multilingual"]
    currentIndex: Math.max(0, root._sherpaProfileKeys.indexOf(root.editSherpaProfile))
    onCurrentIndexChanged: {
      if (currentIndex >= 0 && currentIndex < root._sherpaProfileKeys.length) {
        root.editSherpaProfile = root._sherpaProfileKeys[currentIndex]
      }
    }
  }

  NLabel {
    label: pluginApi?.tr("settings.sherpaProvider") || "sherpa compute provider"
    description: pluginApi?.tr("settings.sherpaProviderDesc") || "ONNX Runtime provider for sherpa-onnx"
    Layout.topMargin: Style.marginS
  }

  NComboBox {
    Layout.fillWidth: true
    model: ["Auto", "CPU", "CUDA"]
    currentIndex: Math.max(0, root._sherpaProviderKeys.indexOf(root.editSherpaProvider))
    onCurrentIndexChanged: {
      if (currentIndex >= 0 && currentIndex < root._sherpaProviderKeys.length) {
        root.editSherpaProvider = root._sherpaProviderKeys[currentIndex]
      }
    }
  }

  NLabel {
    label: pluginApi?.tr("settings.downloadModels") || "Model download"
    description: pluginApi?.tr("settings.downloadModelsDesc") || "Run download_models.sh english (or multilingual) once after install. Includes Silero VAD (~200KB)."
    Layout.topMargin: Style.marginS
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
  }

  // Language
  NLabel {
    label: pluginApi?.tr("settings.language") || "Language"
    description: pluginApi?.tr("settings.languageDesc") || "Auto-detect or pick a specific language"
    Layout.topMargin: Style.marginS
  }

  NComboBox {
    Layout.fillWidth: true
    model: ["Auto-detect", "English", "Spanish", "French", "German", "Italian", "Portuguese", "Dutch", "Polish", "Russian", "Chinese", "Japanese", "Korean", "Arabic", "Hindi", "Turkish", "Vietnamese", "Thai", "Indonesian", "Ukrainian"]
    currentIndex: Math.max(0, root._languageKeys.indexOf(root.editLanguage))
    onCurrentIndexChanged: {
      if (currentIndex >= 0 && currentIndex < root._languageKeys.length) {
        root.editLanguage = root._languageKeys[currentIndex]
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
    Layout.bottomMargin: Style.marginS
  }

  // Optional safety cap (0 = unlimited, session ends on hotkey/mic toggle only)
  NLabel {
    label: pluginApi?.tr("settings.timeout") || "Safety timeout"
    description: pluginApi?.tr("settings.timeoutDesc") || "Optional max seconds (0 = unlimited). Sessions stop only via hotkey or mic click."
    Layout.topMargin: Style.marginS
  }

  NSpinBox {
    Layout.fillWidth: true
    from: 0
    to: 3600
    value: root.editTimeout
    onValueChanged: root.editTimeout = value
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
    Layout.bottomMargin: Style.marginS
  }

  NLabel {
    label: pluginApi?.tr("settings.debug") || "Debug"
    description: pluginApi?.tr("settings.debugDesc") || "Backend controls and log output"
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NButton {
      text: pluginApi?.tr("settings.startBackend") || "Start"
      outlined: true
      visible: {
        var st = pluginApi?.mainInstance?.backendState || "stopped"
        return st === "stopped" || st === "error"
      }
      onClicked: {
        if (pluginApi?.mainInstance) {
          pluginApi.mainInstance.ensureBackend()
        }
      }
    }

    NButton {
      text: pluginApi?.tr("settings.stopBackend") || "Stop"
      outlined: true
      visible: {
        var st = pluginApi?.mainInstance?.backendState || "stopped"
        return st !== "stopped" && st !== "setup" && st !== "stopping"
      }
      onClicked: {
        if (pluginApi?.mainInstance) {
          pluginApi.mainInstance.stopBackend()
        }
      }
    }

  }

  NLabel {
    label: pluginApi?.tr("settings.logs") || "Logs"
    Layout.topMargin: Style.marginS
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 150 * Style.uiScaleRatio
    color: Color.mSurfaceVariant
    radius: Style.radiusM

    NScrollView {
      anchors.fill: parent
      anchors.margins: Style.marginS

      NText {
        id: logText
        text: {
          var mi = pluginApi?.mainInstance
          if (!mi) return pluginApi?.tr("settings.noLogs") || "Plugin not loaded"
          var out = mi.backendStdout || ""
          var err = mi.backendStderr || ""
          var result = ""
          if (out) result += pluginApi?.tr("settings.stdout") || "STDOUT:" + "\n" + out + "\n"
          if (err) result += (result ? "\n" : "") + (pluginApi?.tr("settings.stderr") || "STDERR:") + "\n" + err
          if (!result) result = pluginApi?.tr("settings.noLogs") || "(no output yet)"
          return result
        }
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeXS
        wrapMode: Text.WordWrap
      }
    }
  }

  NButton {
    text: pluginApi?.tr("settings.clearLogs") || "Clear logs"
    outlined: true
    Layout.topMargin: Style.marginS
    onClicked: {
      if (pluginApi?.mainInstance) {
        pluginApi.mainInstance.clearLogs()
      }
    }
  }

  // Called by the settings dialog when user clicks Apply/Save
  function saveSettings() {
    if (!pluginApi) {
      Logger.e("Dictation", "Cannot save: pluginApi is null")
      return
    }

    pluginApi.pluginSettings.engine = root.editEngine
    pluginApi.pluginSettings.sherpaProfile = root.editSherpaProfile
    pluginApi.pluginSettings.sherpaProvider = root.editSherpaProvider
    pluginApi.pluginSettings.language = root.editLanguage
    pluginApi.pluginSettings.recordingTimeout = Math.max(0, Math.min(3600, parseInt(root.editTimeout, 10) || 0))
    pluginApi.saveSettings()

    if (pluginApi?.mainInstance) {
      pluginApi.mainInstance.updateSettings()
    }

    Logger.i("Dictation", "Settings saved")
  }
}
