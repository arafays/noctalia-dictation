import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.Compositor

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

  readonly property string ipcToggleCmd: "qs -c noctalia-shell ipc call plugin:dictation toggle"
  readonly property string ipcStartCmd: "qs -c noctalia-shell ipc call plugin:dictation start"
  readonly property string ipcStopCmd: "qs -c noctalia-shell ipc call plugin:dictation stop"

  readonly property string compositorExample: {
    if (CompositorService.isNiri) {
      return 'bind=Mod+Shift+D { spawn-sh "' + ipcToggleCmd + '"; }'
    }
    if (CompositorService.isHyprland) {
      return "bind = SUPER SHIFT, D, exec, " + ipcToggleCmd
    }
    return ipcToggleCmd
  }

  readonly property string compositorExampleDesc: {
    if (CompositorService.isNiri) {
      return pluginApi?.tr("settings.hotkeys.niriExampleDesc")
          || "Add to your Niri config (e.g. ~/.config/niri/config.kdl):"
    }
    if (CompositorService.isHyprland) {
      return pluginApi?.tr("settings.hotkeys.hyprExampleDesc")
          || "Add to your Hyprland config (e.g. ~/.config/hypr/hyprland.conf):"
    }
    return pluginApi?.tr("settings.hotkeys.genericExampleDesc")
        || "Bind this command in your compositor's keybind config:"
  }

  NLabel {
    label: pluginApi?.tr("settings.hotkeys.title") || "Keyboard shortcuts"
    description: pluginApi?.tr("settings.hotkeys.desc")
        || "Dictation does not register global hotkeys itself. Bind the IPC commands below in your compositor (Niri, Hyprland, etc.). The bar mic button always toggles recording."
    Layout.topMargin: Style.marginS
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: hotkeysCode.implicitHeight + Style.marginS * 2
    color: Color.mSurfaceVariant
    radius: Style.radiusM

    NText {
      id: hotkeysCode
      anchors.fill: parent
      anchors.margins: Style.marginS
      text: (pluginApi?.tr("settings.hotkeys.toggle") || "Toggle session") + ":\n  " + root.ipcToggleCmd
          + "\n\n" + (pluginApi?.tr("settings.hotkeys.start") || "Start") + ":\n  " + root.ipcStartCmd
          + "\n\n" + (pluginApi?.tr("settings.hotkeys.stop") || "Stop") + ":\n  " + root.ipcStopCmd
      color: Color.mOnSurfaceVariant
      pointSize: Style.fontSizeXS
      font.family: "monospace"
      wrapMode: Text.Wrap
    }
  }

  NLabel {
    label: pluginApi?.tr("settings.hotkeys.example") || "Example keybind"
    description: root.compositorExampleDesc
    Layout.topMargin: Style.marginS
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: compositorExampleCode.implicitHeight + Style.marginS * 2
    color: Color.mSurfaceVariant
    radius: Style.radiusM

    NText {
      id: compositorExampleCode
      anchors.fill: parent
      anchors.margins: Style.marginS
      text: root.compositorExample
      color: Color.mOnSurfaceVariant
      pointSize: Style.fontSizeXS
      font.family: "monospace"
      wrapMode: Text.Wrap
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
    Layout.bottomMargin: Style.marginS
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

  property bool editShowOverlay:
    pluginApi?.pluginSettings?.showOverlay ??
    _defaults?.showOverlay ??
    true

  property bool editShowPartial:
    pluginApi?.pluginSettings?.showPartialTranscript ??
    _defaults?.showPartialTranscript ??
    true

  property bool editAutoType:
    pluginApi?.pluginSettings?.autoType ??
    _defaults?.autoType ??
    true

  property bool editVadEnabled:
    pluginApi?.pluginSettings?.vadEnabled ??
    _defaults?.vadEnabled ??
    true

  property real editVadThreshold:
    pluginApi?.pluginSettings?.vadThreshold ??
    _defaults?.vadThreshold ??
    0.4

  property string editOverlayPosition:
    pluginApi?.pluginSettings?.overlayPosition ||
    _defaults?.overlayPosition ||
    "bottom"

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
    label: pluginApi?.tr("settings.behavior") || "Behavior"
    description: pluginApi?.tr("settings.behaviorDesc") || "Overlay, typing, and noise gating"
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.showOverlay") || "Show live overlay"
    description: pluginApi?.tr("settings.showOverlayDesc") || "Floating transcript card while dictating"
    checked: root.editShowOverlay
    onToggled: checked => root.editShowOverlay = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.showPartial") || "Show partial transcript"
    description: pluginApi?.tr("settings.showPartialDesc") || "Italic preview text from the streaming pass"
    checked: root.editShowPartial
    onToggled: checked => root.editShowPartial = checked
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.overlayPosition") || "Overlay position"
    description: pluginApi?.tr("settings.overlayPositionDesc") || "Where the transcript card appears on screen"
    model: [
      { "key": "bottom", "name": pluginApi?.tr("settings.overlayBottom") || "Bottom" },
      { "key": "top", "name": pluginApi?.tr("settings.overlayTop") || "Top" }
    ]
    currentKey: root.editOverlayPosition
    onSelected: key => root.editOverlayPosition = key
    defaultValue: _defaults?.overlayPosition || "bottom"
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.autoType") || "Auto-type on commit"
    description: pluginApi?.tr("settings.autoTypeDesc") || "Type each phrase into the focused window via wtype (off = clipboard only on stop)"
    checked: root.editAutoType
    onToggled: checked => root.editAutoType = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.vadEnabled") || "Noise gate (VAD)"
    description: pluginApi?.tr("settings.vadEnabledDesc") || "Silero VAD skips decode on non-speech audio"
    checked: root.editVadEnabled
    onToggled: checked => root.editVadEnabled = checked
  }

  NLabel {
    visible: root.editVadEnabled
    label: pluginApi?.tr("settings.vadThreshold") || "VAD sensitivity"
    description: (pluginApi?.tr("settings.vadThresholdDesc") || "Higher = stricter (less background noise). Restart backend after change.")
        + " (" + root.editVadThreshold.toFixed(2) + ")"
  }

  NSlider {
    Layout.fillWidth: true
    visible: root.editVadEnabled
    from: 0.1
    to: 0.9
    stepSize: 0.05
    value: root.editVadThreshold
    onValueChanged: root.editVadThreshold = value
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
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
    pluginApi.pluginSettings.showOverlay = root.editShowOverlay
    pluginApi.pluginSettings.showPartialTranscript = root.editShowPartial
    pluginApi.pluginSettings.autoType = root.editAutoType
    pluginApi.pluginSettings.overlayPosition = root.editOverlayPosition
    pluginApi.pluginSettings.vadEnabled = root.editVadEnabled
    pluginApi.pluginSettings.vadThreshold = Math.max(0.1, Math.min(0.9, parseFloat(root.editVadThreshold) || 0.4))
    pluginApi.saveSettings()

    if (pluginApi?.mainInstance) {
      pluginApi.mainInstance.updateSettings()
    }

    Logger.i("Dictation", "Settings saved")
  }
}
