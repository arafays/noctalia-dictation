import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services.Compositor

ColumnLayout {
  id: root

  property var pluginApi: null

  spacing: Style.marginM
  readonly property int preferredWidth: 720 * Style.uiScaleRatio

  readonly property var _defaults: pluginApi?.manifest?.metadata?.defaultSettings
  readonly property bool isSherpaEngine: root.editEngine === "auto" || root.editEngine === "sherpa"
  readonly property bool isFwEngine: root.editEngine === "faster_whisper"

  function _keyModel(keys, names) {
    var out = []
    for (var i = 0; i < keys.length; i++) {
      out.push({ "key": keys[i], "name": names[i] })
    }
    return out
  }

  readonly property var _engineModel: [
    { "key": "auto", "name": pluginApi?.tr("settings.engineAuto") || "Auto (sherpa-onnx)" },
    { "key": "sherpa", "name": pluginApi?.tr("settings.engineSherpa") || "sherpa-onnx two-pass" },
    { "key": "faster_whisper", "name": pluginApi?.tr("settings.engineFw") || "faster-whisper" }
  ]
  readonly property var _sherpaProfileModel: [
    { "key": "auto", "name": pluginApi?.tr("settings.sherpaProfileAuto") || "Auto from language" },
    { "key": "english", "name": pluginApi?.tr("settings.sherpaProfileEnglish") || "English" },
    { "key": "multilingual", "name": pluginApi?.tr("settings.sherpaProfileMultilingual") || "Multilingual" }
  ]
  readonly property var _sherpaProviderModel: [
    { "key": "auto", "name": "Auto" },
    { "key": "cpu", "name": "CPU" },
    { "key": "cuda", "name": "CUDA" }
  ]
  readonly property var _fwModelModel: _keyModel(
    ["tiny", "base", "small", "medium", "large-v2", "large-v3"],
    ["tiny", "base", "small", "medium", "large-v2", "large-v3"]
  )
  readonly property var _fwDeviceModel: [
    { "key": "auto", "name": "Auto" },
    { "key": "cpu", "name": "CPU" },
    { "key": "cuda", "name": "CUDA" }
  ]
  readonly property var _fwComputeModel: [
    { "key": "auto", "name": "Auto" },
    { "key": "int8", "name": "int8" },
    { "key": "int8_float16", "name": "int8_float16" },
    { "key": "float16", "name": "float16" },
    { "key": "float32", "name": "float32" }
  ]
  readonly property var _languageModel: _keyModel(
    ["auto", "en", "es", "fr", "de", "it", "pt", "nl", "pl", "ru", "zh", "ja", "ko", "ar", "hi", "tr", "vi", "th", "id", "uk"],
    ["Auto-detect", "English", "Spanish", "French", "German", "Italian", "Portuguese", "Dutch", "Polish", "Russian", "Chinese", "Japanese", "Korean", "Arabic", "Hindi", "Turkish", "Vietnamese", "Thai", "Indonesian", "Ukrainian"]
  )

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
  property string editFwModel:
    pluginApi?.pluginSettings?.fwModel ||
    pluginApi?.pluginSettings?.model ||
    _defaults?.fwModel ||
    "small"
  property string editFwDevice:
    pluginApi?.pluginSettings?.fwDevice ||
    pluginApi?.pluginSettings?.device ||
    _defaults?.fwDevice ||
    "auto"
  property string editFwComputeType:
    pluginApi?.pluginSettings?.fwComputeType ||
    pluginApi?.pluginSettings?.computeType ||
    _defaults?.fwComputeType ||
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
  property string editStopHotkeyHint:
    pluginApi?.pluginSettings?.stopHotkeyHint ||
    _defaults?.stopHotkeyHint ||
    ""

  property int editSherpaNumThreads:
    pluginApi?.pluginSettings?.sherpaNumThreads ??
    _defaults?.sherpaNumThreads ??
    2
  property real editSherpaMinSpeechSec:
    pluginApi?.pluginSettings?.sherpaMinSpeechSec ??
    _defaults?.sherpaMinSpeechSec ??
    0.2
  property real editSherpaMinSilenceSec:
    pluginApi?.pluginSettings?.sherpaMinSilenceSec ??
    _defaults?.sherpaMinSilenceSec ??
    0.3
  property real editSherpaHangoverSec:
    pluginApi?.pluginSettings?.sherpaHangoverSec ??
    _defaults?.sherpaHangoverSec ??
    0.35
  property real editSherpaEndpointSilence1:
    pluginApi?.pluginSettings?.sherpaEndpointSilence1 ??
    _defaults?.sherpaEndpointSilence1 ??
    2.4
  property real editSherpaEndpointSilence2:
    pluginApi?.pluginSettings?.sherpaEndpointSilence2 ??
    _defaults?.sherpaEndpointSilence2 ??
    1.2
  property int editSherpaMaxActivePaths:
    pluginApi?.pluginSettings?.sherpaMaxActivePaths ??
    _defaults?.sherpaMaxActivePaths ??
    4

  property int editFwBeamSize:
    pluginApi?.pluginSettings?.fwBeamSize ??
    _defaults?.fwBeamSize ??
    5
  property real editFwTemperature:
    pluginApi?.pluginSettings?.fwTemperature ??
    _defaults?.fwTemperature ??
    0
  property string editFwInitialPrompt:
    pluginApi?.pluginSettings?.fwInitialPrompt ||
    _defaults?.fwInitialPrompt ||
    ""
  property bool editFwConditionOnPreviousText:
    pluginApi?.pluginSettings?.fwConditionOnPreviousText ??
    _defaults?.fwConditionOnPreviousText ??
    true
  property real editFwNoSpeechThreshold:
    pluginApi?.pluginSettings?.fwNoSpeechThreshold ??
    _defaults?.fwNoSpeechThreshold ??
    0.6
  property real editFwCompressionRatioThreshold:
    pluginApi?.pluginSettings?.fwCompressionRatioThreshold ??
    _defaults?.fwCompressionRatioThreshold ??
    2.4
  property real editFwSilenceRms:
    pluginApi?.pluginSettings?.fwSilenceRms ??
    _defaults?.fwSilenceRms ??
    0.01
  property real editFwPauseSec:
    pluginApi?.pluginSettings?.fwPauseSec ??
    _defaults?.fwPauseSec ??
    1.5
  property real editFwPartialIntervalSec:
    pluginApi?.pluginSettings?.fwPartialIntervalSec ??
    _defaults?.fwPartialIntervalSec ??
    2.5
  property bool editFwInternalVad:
    pluginApi?.pluginSettings?.fwInternalVad ??
    _defaults?.fwInternalVad ??
    false

  property var depChecks: {
    var mi = pluginApi?.mainInstance
    if (!mi) return []
    void mi._diagnoseRev
    return mi._lastDiagnose?.checks || []
  }
  property bool depChecking: pluginApi?.mainInstance?.diagnoseRunning === true
  property bool depReady: {
    var mi = pluginApi?.mainInstance
    if (!mi) return false
    void mi._diagnoseRev
    return mi._lastDiagnose?.ready === true
  }
  readonly property string pluginDir: pluginApi?.pluginDir || ""

  function runVerifyInstallation() {
    if (!pluginDir) return
    if (!pluginApi?.mainInstance) {
      Logger.w("Dictation", "Cannot verify: plugin Main instance not loaded")
      return
    }
    pluginApi.mainInstance.runDiagnose()
  }

  function migrateLegacySettings() {
    if (!pluginApi?.pluginSettings) return
    var ps = pluginApi.pluginSettings
    if (ps.model && !ps.fwModel) ps.fwModel = ps.model
    if (ps.device && !ps.fwDevice) ps.fwDevice = ps.device
    if (ps.computeType && !ps.fwComputeType) ps.fwComputeType = ps.computeType
  }

  Component.onCompleted: {
    migrateLegacySettings()
    Qt.callLater(runVerifyInstallation)
  }

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

  NLabel {
    label: pluginApi?.tr("settings.engine") || "Speech engine"
    description: root.isFwEngine
        ? (pluginApi?.tr("settings.engineFwDesc")
            || "faster-whisper (CTranslate2): better for accented English. Re-decodes on pauses; first run downloads the model.")
        : (pluginApi?.tr("settings.engineDesc")
            || "sherpa-onnx two-pass streaming with Silero VAD noise gating (Zipformer live + Whisper/SenseVoice finals).")
    Layout.topMargin: Style.marginS
  }

  NComboBox {
    Layout.fillWidth: true
    model: root._engineModel
    currentKey: root.editEngine
    onSelected: key => root.editEngine = key
    defaultValue: _defaults?.engine || "auto"
  }

  NLabel {
    visible: root.isSherpaEngine
    label: pluginApi?.tr("settings.sherpaProfile") || "sherpa model profile"
    description: pluginApi?.tr("settings.sherpaProfileDesc") || "English uses Zipformer+Whisper. Multilingual adds SenseVoice for better non-English accuracy."
    Layout.topMargin: Style.marginS
  }

  NComboBox {
    visible: root.isSherpaEngine
    Layout.fillWidth: true
    model: root._sherpaProfileModel
    currentKey: root.editSherpaProfile
    onSelected: key => root.editSherpaProfile = key
    defaultValue: _defaults?.sherpaProfile || "auto"
  }

  NLabel {
    visible: root.isSherpaEngine
    label: pluginApi?.tr("settings.sherpaProvider") || "sherpa compute provider"
    description: pluginApi?.tr("settings.sherpaProviderDesc") || "ONNX Runtime provider for sherpa-onnx"
    Layout.topMargin: Style.marginS
  }

  NComboBox {
    visible: root.isSherpaEngine
    Layout.fillWidth: true
    model: root._sherpaProviderModel
    currentKey: root.editSherpaProvider
    onSelected: key => root.editSherpaProvider = key
    defaultValue: _defaults?.sherpaProvider || "auto"
  }

  NLabel {
    visible: root.isSherpaEngine
    label: pluginApi?.tr("settings.downloadModels") || "Model download"
    description: pluginApi?.tr("settings.downloadModelsDesc") || "Run download_models.sh english (or multilingual) once after install. Includes Silero VAD (~200KB)."
    Layout.topMargin: Style.marginS
  }

  NDivider {
    visible: root.isSherpaEngine
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
  }

  NLabel {
    visible: root.isSherpaEngine
    label: pluginApi?.tr("settings.sherpaAdvanced") || "sherpa advanced tuning"
    description: pluginApi?.tr("settings.sherpaAdvancedDesc") || "VAD gating and phrase-end detection. Restart backend after changes."
  }

  NSpinBox {
    visible: root.isSherpaEngine
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.sherpaNumThreads") || "CPU threads"
    description: pluginApi?.tr("settings.sherpaNumThreadsDesc") || "ONNX Runtime threads (1–8). More can help on multi-core CPUs."
    from: 1
    to: 8
    value: root.editSherpaNumThreads
    onValueChanged: root.editSherpaNumThreads = value
  }

  NLabel {
    visible: root.isSherpaEngine
    label: pluginApi?.tr("settings.sherpaMinSpeechSec") || "Min speech duration"
    description: (pluginApi?.tr("settings.sherpaMinSpeechSecDesc") || "VAD: minimum voiced segment length.")
        + " (" + root.editSherpaMinSpeechSec.toFixed(2) + " s)"
  }

  NSlider {
    visible: root.isSherpaEngine
    Layout.fillWidth: true
    from: 0.05
    to: 0.5
    stepSize: 0.05
    value: root.editSherpaMinSpeechSec
    onValueChanged: root.editSherpaMinSpeechSec = value
  }

  NLabel {
    visible: root.isSherpaEngine
    label: pluginApi?.tr("settings.sherpaMinSilenceSec") || "Min silence duration"
    description: (pluginApi?.tr("settings.sherpaMinSilenceSecDesc") || "VAD: silence needed to close a speech segment.")
        + " (" + root.editSherpaMinSilenceSec.toFixed(2) + " s)"
  }

  NSlider {
    visible: root.isSherpaEngine
    Layout.fillWidth: true
    from: 0.1
    to: 1.0
    stepSize: 0.05
    value: root.editSherpaMinSilenceSec
    onValueChanged: root.editSherpaMinSilenceSec = value
  }

  NLabel {
    visible: root.isSherpaEngine
    label: pluginApi?.tr("settings.sherpaHangoverSec") || "VAD hangover"
    description: (pluginApi?.tr("settings.sherpaHangoverSecDesc") || "Keep gate open briefly after speech stops (preserves word endings).")
        + " (" + root.editSherpaHangoverSec.toFixed(2) + " s)"
  }

  NSlider {
    visible: root.isSherpaEngine
    Layout.fillWidth: true
    from: 0.1
    to: 0.8
    stepSize: 0.05
    value: root.editSherpaHangoverSec
    onValueChanged: root.editSherpaHangoverSec = value
  }

  NLabel {
    visible: root.isSherpaEngine
    label: pluginApi?.tr("settings.sherpaEndpointSilence1") || "Phrase-end silence (long)"
    description: (pluginApi?.tr("settings.sherpaEndpointSilence1Desc") || "Streaming pass: long trailing silence ends a phrase.")
        + " (" + root.editSherpaEndpointSilence1.toFixed(1) + " s)"
  }

  NSlider {
    visible: root.isSherpaEngine
    Layout.fillWidth: true
    from: 1.0
    to: 4.0
    stepSize: 0.1
    value: root.editSherpaEndpointSilence1
    onValueChanged: root.editSherpaEndpointSilence1 = value
  }

  NLabel {
    visible: root.isSherpaEngine
    label: pluginApi?.tr("settings.sherpaEndpointSilence2") || "Phrase-end silence (short)"
    description: (pluginApi?.tr("settings.sherpaEndpointSilence2Desc") || "Streaming pass: shorter silence can also end a phrase.")
        + " (" + root.editSherpaEndpointSilence2.toFixed(1) + " s)"
  }

  NSlider {
    visible: root.isSherpaEngine
    Layout.fillWidth: true
    from: 0.5
    to: 2.0
    stepSize: 0.1
    value: root.editSherpaEndpointSilence2
    onValueChanged: root.editSherpaEndpointSilence2 = value
  }

  NSpinBox {
    visible: root.isSherpaEngine
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.sherpaMaxActivePaths") || "Streaming beam paths"
    description: pluginApi?.tr("settings.sherpaMaxActivePathsDesc") || "Zipformer search width (1–8). Higher may improve accuracy at CPU cost."
    from: 1
    to: 8
    value: root.editSherpaMaxActivePaths
    onValueChanged: root.editSherpaMaxActivePaths = value
  }

  NLabel {
    visible: root.isFwEngine
    label: pluginApi?.tr("settings.fwModel") || "Whisper model size"
    description: pluginApi?.tr("settings.fwModelDesc") || "small or medium recommended for accented English. Downloads automatically on first use."
    Layout.topMargin: Style.marginS
  }

  NComboBox {
    visible: root.isFwEngine
    Layout.fillWidth: true
    model: root._fwModelModel
    currentKey: root.editFwModel
    onSelected: key => root.editFwModel = key
    defaultValue: _defaults?.fwModel || "small"
  }

  NLabel {
    visible: root.isFwEngine
    label: pluginApi?.tr("settings.fwDevice") || "faster-whisper device"
    description: pluginApi?.tr("settings.fwDeviceDesc") || "CUDA if available; CPU works with int8 quantization"
    Layout.topMargin: Style.marginS
  }

  NComboBox {
    visible: root.isFwEngine
    Layout.fillWidth: true
    model: root._fwDeviceModel
    currentKey: root.editFwDevice
    onSelected: key => root.editFwDevice = key
    defaultValue: _defaults?.fwDevice || "auto"
  }

  NLabel {
    visible: root.isFwEngine
    label: pluginApi?.tr("settings.fwComputeType") || "Compute type"
    description: pluginApi?.tr("settings.fwComputeTypeDesc") || "int8 on CPU; int8_float16 or float16 on GPU. Auto picks a sensible default."
    Layout.topMargin: Style.marginS
  }

  NComboBox {
    visible: root.isFwEngine
    Layout.fillWidth: true
    model: root._fwComputeModel
    currentKey: root.editFwComputeType
    onSelected: key => root.editFwComputeType = key
    defaultValue: _defaults?.fwComputeType || "auto"
  }

  NDivider {
    visible: root.isFwEngine
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
  }

  NLabel {
    visible: root.isFwEngine
    label: pluginApi?.tr("settings.fwAdvanced") || "faster-whisper advanced tuning"
    description: pluginApi?.tr("settings.fwAdvancedDesc")
        || "Decode quality and pause segmentation. For accented English: set Language to English, try medium model, add an initial prompt. Restart backend after changes."
  }

  NSpinBox {
    visible: root.isFwEngine
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.fwBeamSize") || "Beam size"
    description: pluginApi?.tr("settings.fwBeamSizeDesc") || "Wider search (1–10). 5 is default; try 8–10 if words are wrong but latency is OK."
    from: 1
    to: 10
    value: root.editFwBeamSize
    onValueChanged: root.editFwBeamSize = value
  }

  NLabel {
    visible: root.isFwEngine
    label: pluginApi?.tr("settings.fwTemperature") || "Temperature"
    description: (pluginApi?.tr("settings.fwTemperatureDesc") || "0 = deterministic (recommended). Slightly higher (0.2) can help rare pronunciations.")
        + " (" + root.editFwTemperature.toFixed(1) + ")"
  }

  NSlider {
    visible: root.isFwEngine
    Layout.fillWidth: true
    from: 0
    to: 1
    stepSize: 0.1
    value: root.editFwTemperature
    onValueChanged: root.editFwTemperature = value
  }

  NTextInput {
    visible: root.isFwEngine
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.fwInitialPrompt") || "Initial prompt"
    description: pluginApi?.tr("settings.fwInitialPromptDesc")
        || "Optional style hint for Whisper (e.g. \"Indian English technical vocabulary\"). Biases spelling and punctuation."
    placeholderText: pluginApi?.tr("settings.fwInitialPromptPlaceholder") || "Indian English, software development terms"
    text: root.editFwInitialPrompt
    onTextChanged: root.editFwInitialPrompt = text
  }

  NToggle {
    visible: root.isFwEngine
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.fwConditionOnPreviousText") || "Condition on previous text"
    description: pluginApi?.tr("settings.fwConditionOnPreviousTextDesc") || "Use prior phrases as context. Helps continuity; turn off if text repeats."
    checked: root.editFwConditionOnPreviousText
    onToggled: checked => root.editFwConditionOnPreviousText = checked
  }

  NLabel {
    visible: root.isFwEngine
    label: pluginApi?.tr("settings.fwNoSpeechThreshold") || "No-speech threshold"
    description: (pluginApi?.tr("settings.fwNoSpeechThresholdDesc") || "Lower if quiet speech is skipped. Default 0.6.")
        + " (" + root.editFwNoSpeechThreshold.toFixed(2) + ")"
  }

  NSlider {
    visible: root.isFwEngine
    Layout.fillWidth: true
    from: 0.3
    to: 0.9
    stepSize: 0.05
    value: root.editFwNoSpeechThreshold
    onValueChanged: root.editFwNoSpeechThreshold = value
  }

  NLabel {
    visible: root.isFwEngine
    label: pluginApi?.tr("settings.fwCompressionRatioThreshold") || "Hallucination filter"
    description: (pluginApi?.tr("settings.fwCompressionRatioThresholdDesc") || "Lower = stricter rejection of repetitive garbage text. Default 2.4.")
        + " (" + root.editFwCompressionRatioThreshold.toFixed(1) + ")"
  }

  NSlider {
    visible: root.isFwEngine
    Layout.fillWidth: true
    from: 1.5
    to: 3.5
    stepSize: 0.1
    value: root.editFwCompressionRatioThreshold
    onValueChanged: root.editFwCompressionRatioThreshold = value
  }

  NLabel {
    visible: root.isFwEngine
    label: pluginApi?.tr("settings.fwSilenceRms") || "Mic silence gate (RMS)"
    description: (pluginApi?.tr("settings.fwSilenceRmsDesc") || "Audio below this level is treated as silence. Lower if you speak quietly.")
        + " (" + root.editFwSilenceRms.toFixed(3) + ")"
  }

  NSlider {
    visible: root.isFwEngine
    Layout.fillWidth: true
    from: 0.003
    to: 0.03
    stepSize: 0.001
    value: root.editFwSilenceRms
    onValueChanged: root.editFwSilenceRms = value
  }

  NLabel {
    visible: root.isFwEngine
    label: pluginApi?.tr("settings.fwPauseSec") || "Pause before commit"
    description: (pluginApi?.tr("settings.fwPauseSecDesc") || "Seconds of silence before a phrase is typed. Shorter = faster commits.")
        + " (" + root.editFwPauseSec.toFixed(1) + " s)"
  }

  NSlider {
    visible: root.isFwEngine
    Layout.fillWidth: true
    from: 0.5
    to: 3.0
    stepSize: 0.1
    value: root.editFwPauseSec
    onValueChanged: root.editFwPauseSec = value
  }

  NLabel {
    visible: root.isFwEngine
    label: pluginApi?.tr("settings.fwPartialIntervalSec") || "Partial update interval"
    description: (pluginApi?.tr("settings.fwPartialIntervalSecDesc") || "How often to refresh the italic preview while speaking.")
        + " (" + root.editFwPartialIntervalSec.toFixed(1) + " s)"
  }

  NSlider {
    visible: root.isFwEngine
    Layout.fillWidth: true
    from: 1.0
    to: 5.0
    stepSize: 0.5
    value: root.editFwPartialIntervalSec
    onValueChanged: root.editFwPartialIntervalSec = value
  }

  NToggle {
    visible: root.isFwEngine
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.fwInternalVad") || "Whisper internal VAD"
    description: pluginApi?.tr("settings.fwInternalVadDesc") || "Extra Silero VAD inside faster-whisper decode (separate from mic silence gate). Try if long silences confuse the model."
    checked: root.editFwInternalVad
    onToggled: checked => root.editFwInternalVad = checked
  }

  NLabel {
    visible: !root.isFwEngine
    description: pluginApi?.tr("settings.engineFwHint")
        || "Select faster-whisper above to configure Whisper model size and compute options."
    Layout.topMargin: Style.marginXS
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
  }

  NLabel {
    label: pluginApi?.tr("settings.language") || "Language"
    description: pluginApi?.tr("settings.languageDesc")
        || "For non-native English, pick English explicitly instead of Auto-detect — this often improves accuracy with both engines."
  }

  NComboBox {
    Layout.fillWidth: true
    model: root._languageModel
    currentKey: root.editLanguage
    onSelected: key => root.editLanguage = key
    defaultValue: _defaults?.language || "auto"
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
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
    description: root.isFwEngine
        ? (pluginApi?.tr("settings.showPartialFwDesc")
            || "Italic preview while faster-whisper decodes the current phrase")
        : (pluginApi?.tr("settings.showPartialSherpaDesc")
            || pluginApi?.tr("settings.showPartialDesc")
            || "Italic preview from sherpa streaming pass")
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
    label: root.isFwEngine
        ? (pluginApi?.tr("settings.vadEnabledFw") || "Silence detection")
        : (pluginApi?.tr("settings.vadEnabledSherpa")
            || pluginApi?.tr("settings.vadEnabled")
            || "Noise gate (VAD)")
    description: root.isFwEngine
        ? (pluginApi?.tr("settings.vadEnabledFwDesc")
            || "Skip decode during silence; re-decode on pauses (RMS gate)")
        : (pluginApi?.tr("settings.vadEnabledSherpaDesc")
            || pluginApi?.tr("settings.vadEnabledDesc")
            || "Silero VAD skips decode on non-speech audio")
    checked: root.editVadEnabled
    onToggled: checked => root.editVadEnabled = checked
  }

  NLabel {
    visible: root.editVadEnabled && !root.isFwEngine
    label: pluginApi?.tr("settings.vadThreshold") || "VAD sensitivity"
    description: (pluginApi?.tr("settings.vadThresholdDesc") || "Higher = stricter (less background noise). Restart backend after change.")
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

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
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

  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.hotkeys.stopHintLabel") || "Overlay stop key label"
    description: pluginApi?.tr("settings.hotkeys.stopHintDesc")
        || "Optional key combo shown on the live overlay (e.g. Super+Shift+D). Leave empty to hide."
    placeholderText: "Super+Shift+D"
    text: root.editStopHotkeyHint
    onTextChanged: root.editStopHotkeyHint = text
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
    Layout.bottomMargin: Style.marginS
  }

  NLabel {
    label: pluginApi?.tr("settings.deps.title") || "Installation checks"
    description: pluginApi?.tr("settings.deps.desc")
        || "Verify Python packages, speech models, and typing tools before dictating."
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: depList.implicitHeight + Style.marginM * 2
    color: Color.mSurfaceVariant
    radius: Style.radiusM

    ColumnLayout {
      id: depList
      anchors {
        fill: parent
        margins: Style.marginM
      }
      spacing: Style.marginS

      Repeater {
        model: root.depChecks

        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: Style.marginS

          NIcon {
            icon: modelData.ok ? "circle-check-filled" : "alert-triangle-filled"
            color: modelData.ok ? Color.mPrimary : Color.mError
            applyUiScale: false
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            NText {
              text: modelData.label || ""
              color: Color.mOnSurface
              font.weight: Font.Medium
              pointSize: Style.fontSizeS
            }
            NText {
              text: modelData.ok
                  ? (pluginApi?.tr("settings.deps.ok") || "OK")
                  : (modelData.fix || modelData.detail || "")
              color: modelData.ok ? Color.mOnSurfaceVariant : Color.mError
              pointSize: Style.fontSizeXS
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }
          }
        }
      }

      NText {
        visible: root.depChecks.length === 0 && !root.depChecking && !pluginApi?.mainInstance
        text: pluginApi?.tr("settings.deps.noMain") || "Plugin not fully loaded — close and reopen settings, or reload the plugin."
        color: Color.mError
        pointSize: Style.fontSizeS
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }

      NText {
        visible: root.depChecks.length === 0 && !root.depChecking && pluginApi?.mainInstance
        text: pluginApi?.tr("settings.deps.notRun") || "Click Verify installation to run checks."
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
      }

      NText {
        visible: root.depChecking
        text: pluginApi?.tr("settings.deps.checking") || "Checking..."
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
      }
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NButton {
      text: pluginApi?.tr("settings.deps.verify") || "Verify installation"
      outlined: true
      enabled: !root.depChecking && root.pluginDir.length > 0
      onClicked: root.runVerifyInstallation()
    }

    NText {
      visible: root.depChecks.length > 0
      text: root.depReady
          ? (pluginApi?.tr("settings.deps.allOk") || "All checks passed")
          : (pluginApi?.tr("settings.deps.fixNeeded") || "Fix the items above, then verify again")
      color: root.depReady ? Color.mPrimary : Color.mError
      pointSize: Style.fontSizeS
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
    }
  }

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
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }
      }

      Item { Layout.fillWidth: true }

      NButton {
        text: pluginApi?.tr("settings.restartBackend") || "Restart"
        outlined: true
        visible: {
          var st = pluginApi?.mainInstance?.backendState || "stopped"
          return st === "idle" || st === "error" || st === "stopped" || st === "stopping"
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
        return st === "stopped" || st === "error" || st === "stopping"
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
          var result = mi.backendLog || ""
          var err = mi.backendStderr || ""
          var out = mi.backendStdout || ""
          if (err) {
            result += (result ? "\n\n" : "") + (pluginApi?.tr("settings.stderr") || "STDERR:") + "\n" + err
          }
          if (out) {
            result += (result ? "\n\n" : "") + (pluginApi?.tr("settings.stdout") || "STDOUT:") + "\n" + out
          }
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
    pluginApi.pluginSettings.fwModel = root.editFwModel
    pluginApi.pluginSettings.fwDevice = root.editFwDevice
    pluginApi.pluginSettings.fwComputeType = root.editFwComputeType
    pluginApi.pluginSettings.fwBeamSize = Math.max(1, Math.min(10, parseInt(root.editFwBeamSize, 10) || 5))
    pluginApi.pluginSettings.fwTemperature = Math.max(0, Math.min(1, parseFloat(root.editFwTemperature) || 0))
    pluginApi.pluginSettings.fwInitialPrompt = root.editFwInitialPrompt.trim()
    pluginApi.pluginSettings.fwConditionOnPreviousText = root.editFwConditionOnPreviousText
    pluginApi.pluginSettings.fwNoSpeechThreshold = Math.max(0.1, Math.min(0.95, parseFloat(root.editFwNoSpeechThreshold) || 0.6))
    pluginApi.pluginSettings.fwCompressionRatioThreshold = Math.max(1.0, Math.min(4.0, parseFloat(root.editFwCompressionRatioThreshold) || 2.4))
    pluginApi.pluginSettings.fwSilenceRms = Math.max(0.001, Math.min(0.05, parseFloat(root.editFwSilenceRms) || 0.01))
    pluginApi.pluginSettings.fwPauseSec = Math.max(0.5, Math.min(3.0, parseFloat(root.editFwPauseSec) || 1.5))
    pluginApi.pluginSettings.fwPartialIntervalSec = Math.max(0.5, Math.min(5.0, parseFloat(root.editFwPartialIntervalSec) || 2.5))
    pluginApi.pluginSettings.fwInternalVad = root.editFwInternalVad
    pluginApi.pluginSettings.sherpaNumThreads = Math.max(1, Math.min(8, parseInt(root.editSherpaNumThreads, 10) || 2))
    pluginApi.pluginSettings.sherpaMinSpeechSec = Math.max(0.05, Math.min(1.0, parseFloat(root.editSherpaMinSpeechSec) || 0.2))
    pluginApi.pluginSettings.sherpaMinSilenceSec = Math.max(0.05, Math.min(2.0, parseFloat(root.editSherpaMinSilenceSec) || 0.3))
    pluginApi.pluginSettings.sherpaHangoverSec = Math.max(0.05, Math.min(1.5, parseFloat(root.editSherpaHangoverSec) || 0.35))
    pluginApi.pluginSettings.sherpaEndpointSilence1 = Math.max(0.5, Math.min(6.0, parseFloat(root.editSherpaEndpointSilence1) || 2.4))
    pluginApi.pluginSettings.sherpaEndpointSilence2 = Math.max(0.3, Math.min(4.0, parseFloat(root.editSherpaEndpointSilence2) || 1.2))
    pluginApi.pluginSettings.sherpaMaxActivePaths = Math.max(1, Math.min(8, parseInt(root.editSherpaMaxActivePaths, 10) || 4))
    pluginApi.pluginSettings.language = root.editLanguage
    pluginApi.pluginSettings.recordingTimeout = Math.max(0, Math.min(3600, parseInt(root.editTimeout, 10) || 0))
    pluginApi.pluginSettings.showOverlay = root.editShowOverlay
    pluginApi.pluginSettings.showPartialTranscript = root.editShowPartial
    pluginApi.pluginSettings.autoType = root.editAutoType
    pluginApi.pluginSettings.overlayPosition = root.editOverlayPosition
    pluginApi.pluginSettings.stopHotkeyHint = root.editStopHotkeyHint.trim()
    pluginApi.pluginSettings.vadEnabled = root.editVadEnabled
    pluginApi.pluginSettings.vadThreshold = Math.max(0.1, Math.min(0.9, parseFloat(root.editVadThreshold) || 0.4))
    delete pluginApi.pluginSettings.model
    delete pluginApi.pluginSettings.device
    delete pluginApi.pluginSettings.computeType
    pluginApi.saveSettings()

    if (pluginApi?.mainInstance) {
      pluginApi.mainInstance.updateSettings()
    }

    Logger.i("Dictation", "Settings saved")
  }
}
