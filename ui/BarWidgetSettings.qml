import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Opened from the bar widget context menu (Bar quick settings).
// Noctalia shell opens entryPoints.settings for the bar-layout gear and Settings → Plugins.
ColumnLayout {
  id: root

  property var pluginApi: null

  spacing: Style.marginM
  readonly property int preferredWidth: 520 * Style.uiScaleRatio

  readonly property var _defaults: pluginApi?.manifest?.metadata?.defaultSettings
  readonly property string editEngine:
    pluginApi?.pluginSettings?.engine ||
    _defaults?.engine ||
    "auto"
  readonly property bool isFwEngine: root.editEngine === "faster_whisper"

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

  NLabel {
    label: root.pluginApi?.tr("settings.bar.title") || "Bar quick settings"
    description: root.pluginApi?.tr("settings.bar.desc")
        || "Operational toggles for the mic widget. Speech engine and models are in Plugin settings."
    Layout.topMargin: Style.marginS
  }

  NToggle {
    Layout.fillWidth: true
    label: root.pluginApi?.tr("settings.showOverlay") || "Show live overlay"
    description: root.pluginApi?.tr("settings.showOverlayDesc") || "Compact bubble while dictating (click-through; position in settings)"
    checked: root.editShowOverlay
    onToggled: checked => root.editShowOverlay = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: root.pluginApi?.tr("settings.showPartial") || "Show partial transcript"
    description: root.isFwEngine
        ? (root.pluginApi?.tr("settings.showPartialFwDesc")
            || "Italic preview while faster-whisper decodes the current phrase")
        : (root.pluginApi?.tr("settings.showPartialSherpaDesc")
            || root.pluginApi?.tr("settings.showPartialDesc")
            || "Italic preview from sherpa streaming pass")
    checked: root.editShowPartial
    onToggled: checked => root.editShowPartial = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: root.pluginApi?.tr("settings.autoType") || "Auto-type on commit"
    description: root.pluginApi?.tr("settings.autoTypeDesc") || "Type each phrase into the focused window via wtype (off = clipboard only on stop)"
    checked: root.editAutoType
    onToggled: checked => root.editAutoType = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: root.isFwEngine
        ? (root.pluginApi?.tr("settings.vadEnabledFw") || "Silence detection")
        : (root.pluginApi?.tr("settings.vadEnabledSherpa")
            || root.pluginApi?.tr("settings.vadEnabled")
            || "Noise gate (VAD)")
    description: root.isFwEngine
        ? (root.pluginApi?.tr("settings.vadEnabledFwDesc")
            || "Skip decode during silence; re-decode on pauses (RMS gate)")
        : (root.pluginApi?.tr("settings.vadEnabledSherpaDesc")
            || root.pluginApi?.tr("settings.vadEnabledDesc")
            || "Silero VAD skips decode on non-speech audio")
    checked: root.editVadEnabled
    onToggled: checked => root.editVadEnabled = checked
  }

  NLabel {
    visible: root.editVadEnabled && !root.isFwEngine
    label: root.pluginApi?.tr("settings.vadThreshold") || "VAD sensitivity"
    description: (root.pluginApi?.tr("settings.vadThresholdDesc") || "Higher = stricter (less background noise). Restart backend after change.")
        + " (" + root.editVadThreshold.toFixed(2) + ")"
  }

  NSlider {
    Layout.fillWidth: true
    visible: root.editVadEnabled && !root.isFwEngine
    from: 0.1
    to: 0.9
    stepSize: 0.05
    value: root.editVadThreshold
    onValueChanged: root.editVadThreshold = value
  }

  function saveSettings() {
    if (!pluginApi) {
      Logger.e("Dictation", "Cannot save bar settings: pluginApi is null")
      return
    }

    pluginApi.pluginSettings.showOverlay = root.editShowOverlay
    pluginApi.pluginSettings.showPartialTranscript = root.editShowPartial
    pluginApi.pluginSettings.autoType = root.editAutoType
    pluginApi.pluginSettings.vadEnabled = root.editVadEnabled
    pluginApi.pluginSettings.vadThreshold = Math.max(0.1, Math.min(0.9, parseFloat(root.editVadThreshold) || 0.4))
    pluginApi.saveSettings()

    if (pluginApi?.mainInstance) {
      pluginApi.mainInstance.updateSettings()
    }

    Logger.i("Dictation", "Bar widget settings saved")
  }
}
