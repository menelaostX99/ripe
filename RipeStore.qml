pragma Singleton

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// The timer itself: one instance for the whole shell, so a session keeps
// counting (and its sounds keep playing) with the panel closed, and every
// monitor's bar shows the same clock. It is a singleton rather than state on
// the service because a widget hosted by a third-party bar is not handed its
// plugin's service; both sides import this instead.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/ripe"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/ripe"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/ripe"
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/+$/, "")

  // ---- settings (what the user chose) and state (where the timer is)
  property var settings: Model.sanitizeSettings({})
  property string phase: "focus"
  property string status: "idle"
  property real endsAt: 0
  property real pausedMs: 0
  property real plannedMs: 0

  // Which phase just ran out, "" when nothing is waiting to be acknowledged.
  // The time's-up screen (Service.qml) is up for as long as this is set.
  property string alert: ""
  property int alertMinutes: 0

  property bool settingsLoaded: false
  property bool stateLoaded: false
  property bool dirsReady: false

  // Ticks while a session runs; everything on screen derives from it.
  property real now: Date.now()

  readonly property bool running: status === "running"
  readonly property bool paused: status === "paused"
  readonly property bool idle: status === "idle"
  readonly property real phaseMs: Number(settings[phase]) * 60000
  readonly property real totalMs: idle ? phaseMs : Math.max(1, plannedMs)
  readonly property real remainingMs: running ? Math.max(0, endsAt - now) : paused ? pausedMs : phaseMs
  readonly property real progress: idle ? 0 : Math.max(0, Math.min(1, 1 - remainingMs / totalMs))
  readonly property string clockText: Model.clock(remainingMs)

  // ---- sounds
  // Blanket keeps its sounds inside a GResource bundle, so they are unpacked
  // once into the cache and played from there. `soundsState` is "checking"
  // until that has been tried.
  property string soundsState: "checking"
  readonly property bool soundsAvailable: soundsState === "ready"
  // Listening without a timer: the play button in the panel.
  property bool ambient: false
  property string soundError: ""
  readonly property var activeSounds: settings.active
  property bool muted: false
  readonly property bool audible: soundsAvailable && activeSounds.length > 0 && !muted
    && (ambient || (settings.soundsWithFocus && phase === "focus" && running))

  function soundLevel(id) {
    var level = settings.levels[id]
    return level === undefined ? 0.6 : level
  }

  function soundActive(id) {
    return activeSounds.indexOf(id) >= 0
  }

  // ---- settings mutators
  function update(patch) {
    settings = Model.sanitizeSettings(Object.assign({}, settings, patch))
    saveSettings()
  }

  // A new length for a phase. Changing the phase that is on the clock moves
  // its end by the same amount, so "+5" in the middle of a session adds five
  // minutes instead of waiting for the next one.
  function setMinutes(key, minutes) {
    if (Model.PHASES.indexOf(key) < 0) return
    var before = Number(settings[key])
    update((function() { var p = {}; p[key] = minutes; return p })())
    var delta = (Number(settings[key]) - before) * 60000
    if (delta === 0 || key !== phase || idle) return
    var floor = 1000
    if (running) {
      var left = Math.max(floor, endsAt - Date.now() + delta)
      endsAt = Date.now() + left
    } else {
      pausedMs = Math.max(floor, pausedMs + delta)
    }
    plannedMs = Math.max(floor, plannedMs + delta)
    tick()
    saveState()
  }

  function toggleSound(id) {
    var active = activeSounds.slice()
    var at = active.indexOf(id)
    if (at >= 0) active.splice(at, 1)
    else active.push(id)
    update({ active: active })
  }

  function setSoundLevel(id, level) {
    var levels = Object.assign({}, settings.levels)
    levels[id] = level
    var patch = { levels: levels }
    if (!soundActive(id)) patch.active = activeSounds.concat([id])
    update(patch)
  }

  // The panel's play button: start or stop the mix right now, whatever the
  // timer is doing. Stopping during a focus session only silences that
  // session; the next one brings the sounds back.
  function toggleAmbient() {
    if (!soundsAvailable) return
    if (audible) {
      ambient = false
      if (audible) muted = true
      return
    }
    // With nothing picked the button would do nothing; start with rain.
    if (activeSounds.length === 0) update({ active: ["rain"] })
    muted = false
    if (!audible) ambient = true
  }

  // ---- timer
  function tick() {
    now = Date.now()
    if (running && now >= endsAt) finish(false)
  }

  // Runs the current phase for `ms`, or picks a paused one back up.
  function begin(ms) {
    var left = paused && ms === undefined ? pausedMs : (ms === undefined ? phaseMs : ms)
    if (!paused || ms !== undefined) {
      plannedMs = left
      muted = false
    }
    endsAt = Date.now() + left
    status = "running"
    tick()
    saveState()
  }

  function start() {
    if (running) return
    alert = ""
    begin()
  }

  function pause() {
    if (!running) return
    pausedMs = Math.max(0, endsAt - Date.now())
    status = "paused"
    tick()
    saveState()
  }

  function toggle() {
    running ? pause() : start()
  }

  // Back to the start of the current phase.
  function reset() {
    alert = ""
    status = "idle"
    tick()
    saveState()
  }

  // Jump to a phase, e.g. straight to a break.
  function selectPhase(next) {
    if (Model.PHASES.indexOf(next) < 0 || (next === phase && idle)) return
    alert = ""
    phase = next
    status = "idle"
    tick()
    saveState()
  }

  // Leave the current phase early and line up the other one.
  function skip() {
    selectPhase(Model.otherPhase(phase))
  }

  // The phase ran out. `quiet` is for a session that ended while the shell
  // was not running: nothing rings and nothing starts.
  function finish(quiet) {
    var finished = phase
    var minutes = Math.max(1, Math.round(totalMs / 60000))
    phase = Model.otherPhase(finished)
    status = "idle"
    var auto = phase === "focus" ? settings.autoFocus : settings.autoBreaks
    if (!quiet && auto) {
      begin()
    } else {
      tick()
      saveState()
    }
    if (quiet) return
    if (settings.chime) Quickshell.execDetached(["pw-play", "--volume", "0.6", pluginDir + "/chime.wav"])
    if (settings.overlay) {
      alertMinutes = minutes
      alert = finished
    } else {
      announce(finished)
    }
  }

  // ---- the time's-up screen
  function showAlert(kind) {
    if (Model.PHASES.indexOf(kind) < 0) return
    alertMinutes = Number(settings[kind])
    alert = kind
  }

  function dismissAlert() {
    alert = ""
  }

  // The main button: get on with whatever comes next.
  function acceptAlert() {
    alert = ""
    if (!running) begin()
  }

  // Not done yet: a few more minutes of the phase that just ended.
  function extendAlert(minutes) {
    var kind = alert
    if (kind === "") return
    alert = ""
    phase = kind
    status = "idle"
    begin(Math.max(1, minutes) * 60000)
  }

  // After focus: no break, straight back to work.
  function declineAlert() {
    var kind = alert
    alert = ""
    if (kind !== "focus") return
    phase = "focus"
    status = "idle"
    tick()
    saveState()
  }

  // The fallback when the full-screen message is turned off.
  function announce(finished) {
    var title = finished === "focus" ? strings.t("alert.focus.title") : strings.t("alert.break.title")
    var body = (finished === "focus" ? strings.t("alert.focus.body") : strings.t("alert.break.body"))
      .arg(I18n.formatNumber(Number(settings[phase]), 0))
    Quickshell.execDetached(["notify-send", "-a", "Ripe", "-i", pluginDir + "/tomato.svg", "-t", "8000", title, body])
  }

  function statusJson() {
    return JSON.stringify({
      phase: phase,
      status: status,
      remaining: Math.ceil(remainingMs / 1000),
      minutes: Number(settings[phase]),
      alert: alert,
      sounds: audible,
      mix: activeSounds,
      volume: Math.round(settings.master * 100)
    })
  }

  // ---- persistence
  // Dragging a volume changes the settings many times a second; the file is
  // written once the changes stop.
  function saveSettings() {
    if (settingsLoaded && dirsReady) settingsSaver.restart()
  }

  function writeSettings() {
    settingsSaver.stop()
    if (!settingsLoaded || !dirsReady) return
    settingsFile.setText(JSON.stringify(settings, null, 2) + "\n")
  }

  Timer {
    id: settingsSaver
    interval: 300
    onTriggered: root.writeSettings()
  }

  Component.onDestruction: if (settingsSaver.running) writeSettings()

  function saveState() {
    if (!stateLoaded || !dirsReady) return
    stateFile.setText(JSON.stringify({
      phase: phase,
      status: status,
      endsAt: endsAt,
      remainingMs: pausedMs,
      plannedMs: plannedMs
    }) + "\n")
  }

  function applySettings(text) {
    var parsed = {}
    try { parsed = JSON.parse(text) } catch (e) { parsed = {} }
    settings = Model.sanitizeSettings(parsed)
    settingsLoaded = true
  }

  function applyState(text) {
    var parsed = {}
    try { parsed = JSON.parse(text) } catch (e) { parsed = {} }
    var state = Model.sanitizeState(parsed)
    phase = state.phase
    status = state.status
    endsAt = state.endsAt
    pausedMs = state.remainingMs
    plannedMs = state.plannedMs
    stateLoaded = true
    now = Date.now()
    // A session whose end passed while the shell was down is over.
    if (running && now >= endsAt) finish(true)
  }

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // Creates the config, state, and cache directories and unpacks Blanket's
  // sounds. Prints "ready" or "missing" for the sounds.
  Process {
    id: setup
    command: ["bash", root.pluginDir + "/bin/ripe-setup", root.configDir, root.stateDir, root.cacheDir]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.soundsState = text.trim() === "ready" ? "ready" : "missing"
    }
    onExited: {
      root.dirsReady = true
      settingsFile.reload()
      stateFile.reload()
    }
  }

  FileView {
    id: settingsFile
    path: root.dirsReady ? root.configDir + "/settings.json" : ""
    printErrors: false
    atomicWrites: true
    onLoaded: if (!root.settingsLoaded) root.applySettings(text())
    onLoadFailed: if (!root.settingsLoaded) root.applySettings("{}")
  }

  FileView {
    id: stateFile
    path: root.dirsReady ? root.stateDir + "/state.json" : ""
    printErrors: false
    atomicWrites: true
    onLoaded: if (!root.stateLoaded) root.applyState(text())
    onLoadFailed: if (!root.stateLoaded) root.applyState("{}")
  }

  Timer {
    interval: 250
    repeat: true
    running: root.running
    onTriggered: root.tick()
  }

  // One looping player per sound in the mix, alive only while it should be
  // heard, so a silent Ripe holds no audio stream open.
  Instantiator {
    model: Model.SOUNDS
    delegate: Loader {
      id: slot
      required property string modelData
      active: root.audible && root.soundActive(modelData)
      sourceComponent: Item {
        id: voice
        // Fades in, so a sound joining the mix does not land at full volume.
        property real gain: 0
        Behavior on gain { NumberAnimation { duration: Style.duration(600); easing.type: Easing.OutCubic } }
        Component.onCompleted: {
          gain = 1
          player.play()
        }

        MediaPlayer {
          id: player
          source: "file://" + root.cacheDir + "/sounds/" + slot.modelData + ".ogg"
          loops: MediaPlayer.Infinite
          audioOutput: AudioOutput {
            volume: voice.gain * root.settings.master * root.soundLevel(slot.modelData)
          }
          onErrorOccurred: function(error, message) {
            root.soundError = slot.modelData
            console.warn("ripe: could not play " + slot.modelData + ": " + message)
          }
        }
      }
    }
  }
}
