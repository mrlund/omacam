import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var settings: ({})

  readonly property string home: Quickshell.env("HOME")
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? manifest.__sourceDir
    : (home + "/.config/omarchy/plugins/mrlund.omacam")
  readonly property string scriptPath: pluginDir + "/scripts/omacam"
  readonly property string configPath: home + "/.config/omacam/config.json"
  readonly property string previewPath: runtimeDir + "/omacam/preview.jpg"

  property var config: Model.mergeConfig({})
  property bool configLoaded: false
  property bool running: false
  property bool busy: false
  property bool previewing: false
  property bool resumeAfterPreview: false
  property string lastError: ""
  property string statusText: "Off"
  property string inputDevice: ""
  property string virtualDevice: ""
  property bool loopbackLoaded: false
  property bool ready: false
  property bool loopbackSetupTried: false
  readonly property string loopbackSetupPath: pluginDir + "/scripts/install-loopback.sh"
  property string previewUrl: ""
  property int previewSerial: 0
  property int sourceWidth: 3840
  property int sourceHeight: 2160
  readonly property bool capturing: snapshotProcess.running
  readonly property bool probing: probeProcess.running
  property bool startAfterProbe: false
  property var imageBackends: ({ brightness: "sw", contrast: "sw", saturation: "sw" })
  property int previewBrightness: 0
  property int previewContrast: 0
  property int previewSaturation: 0
  property bool snapshotAgain: false

  readonly property var sourceSize: Model.baseSize(config.mode4k === true)

  function notify(title, body) {
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Omacam", "-g", "󰖠", title, body || ""])
  }

  function applyStatus(raw) {
    var parsed = Model.parseJson(raw, null)
    if (!parsed) return
    running = parsed.running === true
    inputDevice = String(parsed.inputDevice || "")
    virtualDevice = String(parsed.virtualDevice || "")
    loopbackLoaded = parsed.loopbackLoaded === true
    if (parsed.error && !running) lastError = Model.elide(parsed.error, 180)
    else if (running) lastError = ""
    statusText = running ? "Live" : (lastError ? "Error" : "Off")
  }

  function applyDoctor(raw) {
    var parsed = Model.parseJson(raw, null)
    if (!parsed) return
    ready = parsed.ready === true
    loopbackLoaded = parsed.loopbackLoaded === true
    inputDevice = String(parsed.inputDevice || inputDevice)
    virtualDevice = String(parsed.virtualDevice || virtualDevice)
    if (!parsed.ready && parsed.missing && parsed.missing.length)
      lastError = "Need: " + parsed.missing.join(", ")
  }

  function writeConfig(next) {
    config = Model.mergeConfig(next || config)
    var payload = JSON.stringify(config, null, 2) + "\n"
    configFile.setText(payload)
  }

  function setCrop(zoom, moveUp, moveRight) {
    var next = Model.mergeConfig(config)
    next.zoom = zoom
    next.moveUp = moveUp
    next.moveRight = moveRight
    config = Model.mergeConfig(next)
  }

  function setImage(brightness, contrast, saturation) {
    var next = Model.mergeConfig(config)
    next.brightness = brightness
    next.contrast = contrast
    next.saturation = saturation
    writeConfig(next)
  }

  function applyImage() {
    applyImageProcess.command = [
      scriptPath, "apply-image",
      String(config.brightness || 0),
      String(config.contrast || 0),
      String(config.saturation || 0)
    ]
    applyImageProcess.running = true
  }

  function probeImageCtrls() {
    if (imageCtrlsProcess.running) return
    imageCtrlsProcess.command = [scriptPath, "image-ctrls"]
    imageCtrlsProcess.running = true
  }

  function setMode4k(enabled) {
    var next = Model.mergeConfig(config)
    next.mode4k = enabled === true
    config = Model.mergeConfig(next)
    sourceWidth = Model.baseSize(config.mode4k).w
    sourceHeight = Model.baseSize(config.mode4k).h
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = [scriptPath, "status"]
    statusProcess.running = true
  }

  function doctor() {
    if (doctorProcess.running) return
    doctorProcess.command = [scriptPath, "doctor"]
    doctorProcess.running = true
  }

  readonly property string decoder: String(config && config.decoder ? config.decoder : "auto")
  property string lastProbeDetail: ""

  function decoderNeedsProbe() {
    return decoder !== "cpu" && decoder !== "cuda"
  }

  function probeDecoder(force) {
    if (probeProcess.running || snapshotProcess.running) return
    if (!force && !decoderNeedsProbe()) return
    lastProbeDetail = ""
    probeProcess.command = force ? [scriptPath, "probe-decoder", "--force"] : [scriptPath, "probe-decoder"]
    probeProcess.running = true
  }

  function start() {
    if (busy) return
    if (probeProcess.running) {
      startAfterProbe = true
      return
    }
    writeConfig(config)
    busy = true
    lastError = ""
    startProcess.command = [scriptPath, "start"]
    startProcess.running = true
  }

  function stop() {
    if (busy) return
    busy = true
    stopProcess.command = [scriptPath, "stop"]
    stopProcess.running = true
  }

  function toggle() {
    if (running) stop()
    else start()
  }

  function beginPreview() {
    previewing = true
    resumeAfterPreview = running
    if (running) {
      busy = true
      stopProcess.command = [scriptPath, "stop"]
      stopProcess.running = true
    } else {
      probeImageCtrls()
      takeSnapshot()
    }
  }

  function finishPreview(shouldStart) {
    previewing = false
    if (shouldStart || resumeAfterPreview) {
      resumeAfterPreview = false
      start()
    } else {
      resumeAfterPreview = false
    }
  }

  function takeSnapshot() {
    if (snapshotProcess.running) {
      snapshotAgain = true
      return
    }
    sourceWidth = sourceSize.w
    sourceHeight = sourceSize.h
    writeConfig(config)
    snapshotProcess.command = [
      scriptPath, "snapshot", previewPath,
      String(config.brightness || 0),
      String(config.contrast || 0),
      String(config.saturation || 0)
    ]
    snapshotProcess.running = true
  }

  Component.onCompleted: {
    doctor()
    refresh()
  }

  Timer {
    id: poll
    interval: running || busy ? 2000 : 8000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    onLoaded: {
      root.config = Model.mergeConfig(Model.parseJson(text(), {}))
      root.sourceWidth = Model.baseSize(root.config.mode4k).w
      root.sourceHeight = Model.baseSize(root.config.mode4k).h
      root.configLoaded = true
    }
    onLoadFailed: {
      root.config = Model.mergeConfig({})
      root.configLoaded = true
      root.writeConfig(root.config)
    }
  }

  Process {
    id: statusProcess
    running: false
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) root.applyStatus(statusOut.text)
      else if (!root.running) root.lastError = Model.elide(statusErr.text || statusOut.text, 180)
    }
  }

  Process {
    id: doctorProcess
    running: false
    stdout: StdioCollector { id: doctorOut; waitForEnd: true }
    stderr: StdioCollector { id: doctorErr; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) root.applyDoctor(doctorOut.text)
      else root.lastError = Model.elide(doctorErr.text || doctorOut.text, 180)
    }
  }

  Process {
    id: startProcess
    running: false
    stdout: StdioCollector { id: startOut; waitForEnd: true }
    stderr: StdioCollector { id: startErr; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        root.busy = false
        root.applyStatus(startOut.text)
        root.lastError = ""
        root.refresh()
        return
      }
      var err = String(startErr.text || startOut.text || "")
      if (!root.loopbackSetupTried && err.indexOf("LOOPBACK_MISSING") !== -1) {
        root.loopbackSetupTried = true
        root.lastError = "Need permission to load the virtual camera (once)"
        root.notify("Omacam", "Enter your password to load the virtual camera. This is only needed once.")
        loopbackSetupProcess.command = ["pkexec", root.loopbackSetupPath]
        loopbackSetupProcess.running = true
        return
      }
      root.busy = false
      root.running = false
      root.lastError = Model.elide(err, 220)
      root.notify("Omacam could not start", root.lastError)
      root.refresh()
    }
  }

  Process {
    id: loopbackSetupProcess
    running: false
    stdout: StdioCollector { id: loopbackOut; waitForEnd: true }
    stderr: StdioCollector { id: loopbackErr; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        root.lastError = ""
        if (root.decoderNeedsProbe()) {
          root.startAfterProbe = true
          root.probeDecoder()
          if (root.probing) return
        }
        startProcess.command = [root.scriptPath, "start"]
        startProcess.running = true
        return
      }
      root.busy = false
      root.running = false
      root.lastError = "Virtual camera module not loaded. Run: sudo " + root.loopbackSetupPath
      root.notify("Omacam could not start", root.lastError)
      root.refresh()
    }
  }

  Process {
    id: stopProcess
    running: false
    stdout: StdioCollector { id: stopOut; waitForEnd: true }
    stderr: StdioCollector { id: stopErr; waitForEnd: true }
    onExited: function(code) {
      root.busy = false
      if (code === 0) root.applyStatus(stopOut.text)
      root.running = false
      root.statusText = "Off"
      if (code !== 0) root.lastError = Model.elide(stopErr.text || stopOut.text, 180)
      root.refresh()
      if (root.previewing) {
        root.probeImageCtrls()
        root.takeSnapshot()
      }
    }
  }

  Process {
    id: imageCtrlsProcess
    running: false
    stdout: StdioCollector { id: imageCtrlsOut; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) return
      var parsed = Model.parseJson(imageCtrlsOut.text, null)
      if (!parsed || !parsed.controls) return
      var next = { brightness: "sw", contrast: "sw", saturation: "sw" }
      var keys = ["brightness", "contrast", "saturation"]
      for (var i = 0; i < keys.length; i++) {
        var key = keys[i]
        if (parsed.controls[key] && parsed.controls[key].backend === "hw") next[key] = "hw"
      }
      root.imageBackends = next
    }
  }

  Process {
    id: applyImageProcess
    running: false
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: probeProcess
    running: false
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    stderr: StdioCollector { id: probeErr; waitForEnd: true }
    onExited: function(code) {
      var parsed = Model.parseJson(probeOut.text, {})
      var decoder = String(parsed.decoder || (code === 0 ? "" : "cpu"))
      root.lastProbeDetail = String(parsed.detail || probeErr.text || "")
      if (decoder === "cpu" || decoder === "cuda") {
        var next = Model.mergeConfig(root.config)
        next.decoder = decoder
        root.config = next
      }
      if (root.startAfterProbe) {
        root.startAfterProbe = false
        root.start()
      }
    }
  }

  Process {
    id: snapshotProcess
    running: false
    stdout: StdioCollector { id: snapOut; waitForEnd: true }
    stderr: StdioCollector { id: snapErr; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        var parsed = Model.parseJson(snapOut.text, {})
        root.sourceWidth = Number(parsed.width || root.sourceSize.w)
        root.sourceHeight = Number(parsed.height || root.sourceSize.h)
        root.previewBrightness = Number(parsed.brightness || 0)
        root.previewContrast = Number(parsed.contrast || 0)
        root.previewSaturation = Number(parsed.saturation || 0)
        root.previewSerial += 1
        root.previewUrl = "file://" + root.previewPath + "?t=" + root.previewSerial
        root.lastError = ""
        root.probeDecoder()
        if (root.snapshotAgain) {
          root.snapshotAgain = false
          root.takeSnapshot()
        }
      } else {
        root.previewUrl = ""
        root.lastError = Model.elide(snapErr.text || snapOut.text, 220)
        if (root.snapshotAgain) {
          root.snapshotAgain = false
          root.takeSnapshot()
        }
      }
    }
  }
}
