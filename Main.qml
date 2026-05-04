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
  property var history: []
  property bool pendingStart: false
  property int _retryCount: 0
  property bool _venvReady: false

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

  Process {
    id: _backendProcess

    stdout: StdioCollector {
      onStreamFinished: Logger.d("Dictation", "backend stdout:", this.text)
    }
    stderr: StdioCollector {
      onStreamFinished: Logger.w("Dictation", "backend stderr:", this.text)
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
    return [venvPython, backendScript].concat(args)
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
    if ((backendState === "stopped" || backendState === "error" || backendState === "setup") && !_launchingBackend) {
      _retryCount = 0
      launchBackend()
    }
  }

  function startRecording() {
    if (backendState !== "idle") {
      Logger.w("Dictation", "Cannot start recording: backend is", backendState)
      return
    }
    Quickshell.execDetached(pythonCmd(["start"]))
  }

  function stopRecording() {
    Quickshell.execDetached(pythonCmd(["stop"]))
  }

  function toggleRecording() {
    if (backendState === "recording") {
      stopRecording()
    } else {
      pendingStart = true
      ensureBackend()
      if (backendState === "idle") {
        pendingStart = false
        startRecording()
      }
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
    var entry = { text: text, timestamp: Date.now() }
    history = [...history, entry]
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
          root.backendMessage = data.message || ""

          if (data.state === "error" && data.message) {
            root.sendErrorNotification(data.message)
          }

          if (root.pendingStart && data.state === "idle" &&
              (data.message === "ready" || data.message === "settings updated" || data.message === "done" || data.message === "silence")) {
            root.pendingStart = false
            root.startRecording()
          }

          if (_launchingBackend && data.state !== "stopped") {
            _launchingBackend = false
            _launchGuardTimer.stop()
          }
        }

        if (data.text && data.text.length > 0) {
          root.addHistoryEntry(data.text)
          root.sendNotification(data.text)
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

  Component.onCompleted: {
    if (pluginApi) {
      loadHistory()
    }
    Logger.i("Dictation", "plugin loaded, pluginDir:", pluginDir)
    Logger.i("Dictation", "backendScript:", backendScript, "venvPython:", venvPython)
    // Kill any orphaned backend from previous session, then start fresh
    cleanupOrphanedBackend()
    _startupDelayTimer.start()
  }
}