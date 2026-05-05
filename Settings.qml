import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  spacing: Style.marginM

  readonly property var _modelKeys: ["tiny", "base", "small", "medium", "large-v3"]
  readonly property var _languageKeys: ["auto", "en", "es", "fr", "de", "it", "pt", "nl", "pl", "ru", "zh", "ja", "ko", "ar", "hi", "tr", "vi", "th", "id", "uk"]
  readonly property var _deviceKeys: ["auto", "cpu", "cuda"]
  readonly property var _computeTypeKeys: ["int8", "float16", "float32"]

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
      case "stopping": return Color.mSecondaryContainer
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

  // Model
  NLabel {
    label: pluginApi?.tr("settings.model") || "Whisper model"
    description: pluginApi?.tr("settings.modelDesc") || "Larger models are more accurate but slower"
  }

  NComboBox {
    Layout.fillWidth: true
    model: ["Tiny", "Base", "Small", "Medium", "Large v3"]
    currentIndex: Math.max(0, root._modelKeys.indexOf(root.editModel))
    onCurrentIndexChanged: {
      if (currentIndex >= 0 && currentIndex < root._modelKeys.length) {
        root.editModel = root._modelKeys[currentIndex]
      }
    }
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

  // Device
  NLabel {
    label: pluginApi?.tr("settings.device") || "Compute device"
    description: pluginApi?.tr("settings.deviceDesc") || "Auto picks CUDA if available"
    Layout.topMargin: Style.marginS
  }

  NComboBox {
    Layout.fillWidth: true
    model: ["Auto", "CPU", "CUDA"]
    currentIndex: Math.max(0, root._deviceKeys.indexOf(root.editDevice))
    onCurrentIndexChanged: {
      if (currentIndex >= 0 && currentIndex < root._deviceKeys.length) {
        root.editDevice = root._deviceKeys[currentIndex]
      }
    }
  }

  // Compute type
  NLabel {
    label: pluginApi?.tr("settings.computeType") || "Compute type"
    description: pluginApi?.tr("settings.computeTypeDesc") || "int8 is fastest on CPU, float16 for GPU"
    Layout.topMargin: Style.marginS
  }

  NComboBox {
    Layout.fillWidth: true
    model: ["INT8", "Float 16", "Float 32"]
    currentIndex: Math.max(0, root._computeTypeKeys.indexOf(root.editComputeType))
    onCurrentIndexChanged: {
      if (currentIndex >= 0 && currentIndex < root._computeTypeKeys.length) {
        root.editComputeType = root._computeTypeKeys[currentIndex]
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
    Layout.bottomMargin: Style.marginS
  }

  // VAD toggle
  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.vad") || "Voice activity detection"
    description: pluginApi?.tr("settings.vadDesc") || "Automatically stop recording during silence"
    checked: root.editVad
    onCheckedChanged: root.editVad = checked
  }

  // Recording timeout
  NLabel {
    label: pluginApi?.tr("settings.timeout") || "Recording timeout"
    description: pluginApi?.tr("settings.timeoutDesc") || "Maximum seconds to record before auto-stop"
    Layout.topMargin: Style.marginS
  }

  NSpinBox {
    Layout.fillWidth: true
    from: 5
    to: 300
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

    pluginApi.pluginSettings.model = root.editModel
    pluginApi.pluginSettings.language = root.editLanguage
    pluginApi.pluginSettings.device = root.editDevice
    pluginApi.pluginSettings.computeType = root.editComputeType
    pluginApi.pluginSettings.vadEnabled = root.editVad
    pluginApi.pluginSettings.recordingTimeout = Math.max(5, Math.min(300, parseInt(root.editTimeout, 10) || 30))
    pluginApi.saveSettings()

    if (pluginApi?.mainInstance) {
      pluginApi.mainInstance.updateSettings()
    }

    Logger.i("Dictation", "Settings saved")
  }
}
