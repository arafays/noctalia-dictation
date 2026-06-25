import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null
  property string backendState: "stopped"
  property string backendMessage: ""
  property string liveTranscript: ""
  property string partialTranscript: ""
  property var history: []
  property bool pendingStart: false
  property int _retryCount: 0
  property string _lastErrorNotified: ""
  property bool _venvReady: false
  property var panelScreen: null

  onPluginApiChanged: {
    if (pluginApi) {
      loadHistory()
    }
  }

  readonly property string pluginDir: pluginApi?.pluginDir || ""
  readonly property string venvPython: pluginDir + "/.venv/bin/python"
  readonly property string backendScript: pluginDir + "/dictation_backend.py"
  readonly property string setupScript: pluginDir + "/setup.sh"

  property bool _launchingBackend: false
  property string backendStdout: ""
  property string backendStderr: ""
  property bool _useSystemPython: false

  Process {
    id: _probeProcess
    command: ["sh", "-c", "python3 -c 'import sherpa_onnx, sounddevice, numpy' 2>/dev/null && echo system-python-ready"]

    stdout: StdioCollector {
      id: _probeStdout
      onStreamFinished: {
        if (text.trim() === "system-python-ready") {
          root._useSystemPython = true
          root._venvReady = true
          Logger.i("Dictation", "system Python has required packages, using it directly")
        } else {
          root._useSystemPython = false
          Logger.i("Dictation", "system Python missing packages, will use venv")
        }
        // Kill any orphaned backend from previous session now that we know which interpreter to use
        root.cleanupOrphanedBackend()
        root._startupDelayTimer.start()
      }
    }
  }

  Process {
    id: _setupProcess

    onRunningChanged: {
      if (running) {
        Logger.i("Dictation", "starting venv setup:", setupScript)
      }
      if (!running) {
        var out = _setupStdout.text.trim()
        var err = _setupStderr.text.trim()
        Logger.i("Dictation", "venv setup finished, stdout:", out, "stderr:", err)
        if (out === "venv-ready") {
          root._venvReady = true
          Logger.i("Dictation", "venv setup complete")
          root.ensureBackend()
        } else {
          root.backendState = "error"
          root.backendMessage = "Failed to set up Python environment"
          Logger.e("Dictation", "venv setup failed, stderr:", err)
          root.sendErrorNotification("Failed to set up Python environment")
        }
      }
    }

    stdout: StdioCollector {
      id: _setupStdout
    }
    stderr: StdioCollector {
      id: _setupStderr
    }
  }

  Timer {
    id: _launchGuardTimer
    interval: 60000
    onTriggered: {
      root._launchingBackend = false
      if (root.backendState === "starting") {
        root.backendState = "error"
        root.backendMessage = "Backend failed to start (timeout)"
        Logger.e("Dictation", "backend launch timed out after 60s")
        root.sendErrorNotification("Backend failed to start (timeout)")
      }
    }
    running: false
  }

  Timer {
    id: _retryTimer
    interval: 3000
    onTriggered: {
      if (root.backendState === "error" && root._retryCount < 3) {
        root._retryCount++
        Logger.i("Dictation", "retrying backend start, attempt", root._retryCount)
        root.launchBackend()
      } else if (root.backendState === "error" && root._retryCount >= 3) {
        root.sendErrorNotification("Backend failed after 3 retries")
      }
    }
    running: false
  }

  Timer {
    id: _restartDelayTimer
    interval: 500
    onTriggered: root.ensureBackend()
  }

  Timer {
    id: _pendingStartTimeout
    interval: 15000
    onTriggered: {
      if (root.pendingStart) {
        root.pendingStart = false
        root.sendErrorNotification(pluginApi?.tr("notification.timeout") || "Backend not ready, try again")
      }
    }
  }

  Timer {
    id: _logPollTimer
    interval: 500
    running: _backendProcess.running
    repeat: true
    onTriggered: {
      var outText = _backendStdoutCol.text || ""
      var errText = _backendStderrCol.text || ""
      if (outText && outText !== root.backendStdout) root.backendStdout = outText
      if (errText && errText !== root.backendStderr) root.backendStderr = errText
    }
  }

  Process {
    id: _backendProcess

    stdout: StdioCollector {
      id: _backendStdoutCol
      onStreamFinished: {
        Logger.d("Dictation", "backend stdout:", this.text)
        root.backendStdout = this.text || ""
      }
    }
    stderr: StdioCollector {
      id: _backendStderrCol
      onStreamFinished: {
        Logger.w("Dictation", "backend stderr:", this.text)
        root.backendStderr = this.text || ""
      }
    }

    onRunningChanged: {
      if (!running && root.backendState === "starting") {
        root._launchingBackend = false
        _launchGuardTimer.stop()
        root.backendState = "error"
        root.backendMessage = "Backend process exited unexpectedly"
        Logger.e("Dictation", "backend process exited unexpectedly, stderr:", _backendProcess.stderr?.text || "(none)")
        _retryTimer.restart()
      } else if (!running) {
        root._launchingBackend = false
        _launchGuardTimer.stop()
        Logger.i("Dictation", "backend process stopped")
      }
    }
  }

  function pythonCmd(args) {
    var py = root._useSystemPython ? "python3" : venvPython
    return [py, backendScript].concat(args)
  }

  function checkVenv() {
    if (!_venvReady) {
      Logger.i("Dictation", "setting up Python venv...")
      backendState = "setup"
      backendMessage = "installing dependencies"
      _setupProcess.exec(["sh", setupScript])
    }
  }

  function launchBackend() {
    if (backendState === "stopped" || backendState === "error" || backendState === "setup") {
      _launchingBackend = true
      backendState = "starting"
      backendMessage = "launching backend"
      _launchGuardTimer.restart()
      var cmd = pythonCmd(["server"])
      Logger.i("Dictation", "launching backend:", JSON.stringify(cmd))
      Logger.i("Dictation", "venvPython exists check - path:", venvPython)
      _backendProcess.exec(cmd)
    }
  }

  function ensureBackend() {
    if (!_venvReady) {
      Logger.i("Dictation", "venv not ready, running setup first")
      checkVenv()
      return
    }
    if ((backendState === "stopped" || backendState === "error" || backendState === "setup" || backendState === "stopping") && !_launchingBackend) {
      _retryCount = 0
      launchBackend()
    }
  }

  function restartBackend() {
    Quickshell.execDetached(pythonCmd(["exit"]))
    backendState = "stopping"
    _venvReady = true
    _retryCount = 0
    _restartDelayTimer.restart()
  }

  function stopBackend() {
    Quickshell.execDetached(pythonCmd(["exit"]))
    backendState = "stopping"
  }

  function clearLogs() {
    backendStdout = ""
    backendStderr = ""
  }

  function startRecording() {
    if (backendState !== "idle") {
      Logger.w("Dictation", "Cannot start recording: backend is", backendState)
      return
    }
    liveTranscript = ""
    partialTranscript = ""
    Quickshell.execDetached(pythonCmd(["start"]))
  }

  function stopRecording() {
    Quickshell.execDetached(pythonCmd(["stop"]))
  }

  function sessionActive() {
    return backendState === "recording" || backendState === "transcribing"
  }

  function toggleRecording() {
    if (sessionActive()) {
      pendingStart = false
      _pendingStartTimeout.stop()
      stopRecording()
      return
    }
    if (backendState === "error") {
      pendingStart = true
      _pendingStartTimeout.restart()
      _retryCount = 0
      _lastErrorNotified = ""
      launchBackend()
      return
    }
    pendingStart = true
    _pendingStartTimeout.restart()
    ensureBackend()
    if (backendState === "idle") {
      pendingStart = false
      _pendingStartTimeout.stop()
      startRecording()
    }
  }

  function updateSettings() {
    Quickshell.execDetached(pythonCmd(["update_settings"]))
  }

  function clearHistory() {
    history = []
    if (pluginApi) {
      pluginApi.pluginSettings.history = []
      pluginApi.saveSettings()
    }
  }

  function addHistoryEntry(text) {
    const MAX_HISTORY = 500
    var entry = { text: text, timestamp: Date.now() }
    history = [...history, entry]
    if (history.length > MAX_HISTORY) {
      history = history.slice(history.length - MAX_HISTORY)
    }
    if (pluginApi) {
      pluginApi.pluginSettings.history = history
      pluginApi.saveSettings()
    }
  }

  function loadHistory() {
    var saved = pluginApi?.pluginSettings?.history
    if (saved && Array.isArray(saved)) {
      // Migrate old string entries to object format
      var needsMigration = false
      history = saved.map(function(item) {
        if (typeof item === "string") {
          needsMigration = true
          return { text: item, timestamp: null }
        }
        return item
      })
      // Persist migrated format
      if (needsMigration && pluginApi) {
        pluginApi.pluginSettings.history = history
        pluginApi.saveSettings()
      }
    } else {
      history = []
    }
  }

  function sendNotification(text) {
    var preview = text.length > 80 ? text.substring(0, 80) + "..." : text
    ToastService.showNotice("Transcribed: " + preview)
  }

  function sendErrorNotification(message) {
    ToastService.showNotice("Dictation: " + message)
  }

  IpcHandler {
    target: "plugin:dictation"

    function toggle() {
      root.toggleRecording()
    }

    function start() {
      root.ensureBackend()
      if (root.backendState === "idle") {
        root.startRecording()
      } else {
        root.pendingStart = true
      }
    }

    function stop() {
      root.stopRecording()
    }

    function status() {
      return root.backendState
    }

    function setStatus(jsonStr: string) {
      try {
        var data = JSON.parse(jsonStr)
        Logger.d("Dictation", "IPC setStatus:", JSON.stringify(data))
        if (data.state !== undefined) {
          root.backendState = data.state
          if (data.state === "idle" && data.message === "ready" && data.engine) {
            root.backendMessage = data.engine
          } else {
            root.backendMessage = data.message || ""
          }

          if (data.engine !== undefined && data.engine.length > 0 && data.state === "recording") {
            root.backendMessage = data.engine
          }

          if (data.liveTranscript !== undefined) {
            root.liveTranscript = data.liveTranscript
          }
          if (data.partialTranscript !== undefined) {
            root.partialTranscript = data.partialTranscript
          }

          if (data.state === "idle" || data.state === "error" || data.state === "stopped") {
            root.liveTranscript = ""
            root.partialTranscript = ""
          }

          if (data.state === "error" && data.message) {
            if (root._lastErrorNotified !== data.message) {
              root._lastErrorNotified = data.message
              root.sendErrorNotification(data.message)
            }
            if (root._retryCount < 3 && !_retryTimer.running) {
              _retryTimer.restart()
            }
          }

          if (data.state === "idle" && data.message === "ready") {
            root._lastErrorNotified = ""
            root._retryCount = 0
          }

          if (root.pendingStart && data.state === "idle" &&
              (data.message === "ready" || data.message === "settings updated" || data.message === "silence" || data.message === "copied" || data.message === "no_speech")) {
            root.pendingStart = false
            _pendingStartTimeout.stop()
            root.startRecording()
          }

          if (_launchingBackend && data.state !== "stopped") {
            _launchingBackend = false
            _launchGuardTimer.stop()
          }
        }

          if (data.state === "idle" && data.message === "copied" && data.text && data.text.length > 0) {
            root.addHistoryEntry(data.text)
            ToastService.showNotice(pluginApi?.tr("notification.copied") || "Transcription copied to clipboard")
          } else if (data.state === "idle" && data.message === "no_speech") {
            ToastService.showNotice(pluginApi?.tr("notification.noSpeech") || "No speech detected")
          } else if (data.state === "idle" && data.text && data.text.length > 0 && data.message !== "copied") {
          root.addHistoryEntry(data.text)
        }
      } catch (e) {
        Logger.w("Dictation", "failed to parse status:", e)
      }
    }
  }

  function cleanupOrphanedBackend() {
    // Send exit signal to any orphaned backend from previous shell session
    Logger.i("Dictation", "cleaning up any orphaned backend...")
    Quickshell.execDetached(pythonCmd(["exit"]))
  }

  Timer {
    id: _startupDelayTimer
    interval: 2000
    onTriggered: {
      Logger.i("Dictation", "startup delay complete, launching backend")
      root.ensureBackend()
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: TranscriptOverlay {
      required property var modelData

      screen: modelData
      pluginApi: root.pluginApi
      mainInstance: root
    }
  }

  Component.onCompleted: {
    if (pluginApi) {
      loadHistory()
    }
    Logger.i("Dictation", "plugin loaded, pluginDir:", pluginDir)
    Logger.i("Dictation", "backendScript:", backendScript, "venvPython:", venvPython)
    // Probe system Python first; cleanup and backend launch happen in the probe callback
    _probeProcess.running = true
  }
}
