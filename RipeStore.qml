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

  // A session began from rest, and a phase ran out: the panel and the bar
  // mark both moments.
  signal started()
  signal finished(string phase)

  // Which phase just ran out, "" when nothing is waiting to be acknowledged.
  // The time's-up screen (Service.qml) is up for as long as this is set.
  property string alert: ""
  property int alertMinutes: 0
  // A time's-up screen that is waiting for the lock screen to go away.
  property string heldAlert: ""
  property int heldAlertMinutes: 0

  property bool settingsLoaded: false
  property bool stateLoaded: false
  property bool dirsReady: false

  // Ticks while a session runs; everything on screen derives from it.
  property real now: Date.now()

  readonly property bool running: status === "running"
  readonly property bool paused: status === "paused"
  readonly property bool idle: status === "idle"
  readonly property bool focusing: running && phase === "focus"
  readonly property bool loaded: settingsLoaded && stateLoaded
  readonly property real phaseMs: Number(settings[phase]) * 60000
  // The length of the session on the clock, which "+5" may have moved away
  // from the saved length of its phase.
  readonly property int sessionMinutes: idle ? Number(settings[phase]) : Math.max(1, Math.round(plannedMs / 60000))
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

  // ---- quiet and awake
  // While a focus session runs, Ripe can silence notifications and keep the
  // screen from sleeping. Both are Omarchy's own switches, the ones behind
  // the bell and the mug among the bar's indicators, so what Ripe has done
  // shows there. Each is flipped only when it was off and handed back when
  // focus ends; `held` remembers which are Ripe's to hand back, across a
  // shell restart. (A Wayland idle inhibitor of Ripe's own would be more
  // self-contained, but Hyprland does not honour one held by a shell
  // surface, so it would not keep anything awake.)
  property bool heldDnd: false
  property bool heldAwake: false
  readonly property bool wantDnd: loaded && settings.focusDnd && focusing
  readonly property bool wantAwake: loaded && settings.keepAwake && focusing
  property int syncTries: 0

  // Calls one of the shell's own IPC handlers in-process. Returns its
  // answer, or null when the shell has no such handler (yet).
  function ask(target, method, args) {
    try {
      var result = IpcRegistry.call(target, method, args || [])
      return result && result.ran ? String(result.output) : null
    } catch (e) {
      return null
    }
  }

  function screenLocked() {
    return ask("lock", "isLocked") === "true"
  }

  function syncSession() {
    if (!loaded) return
    var unanswered = false

    if (wantDnd && !heldDnd) {
      var dnd = ask("notifications", "isDnd")
      if (dnd === null) unanswered = true
      else if (dnd === "off" && ask("notifications", "setDnd", ["on"]) !== null) heldDnd = true
    } else if (!wantDnd && heldDnd) {
      if (ask("notifications", "setDnd", ["off"]) === null) unanswered = true
      else heldDnd = false
    }

    if (wantAwake && !heldAwake) {
      var answer = ask("idle", "status")
      var awake = false
      try { awake = JSON.parse(answer).stayAwake === true } catch (e) { awake = false }
      if (answer === null) unanswered = true
      else if (!awake && ask("idle", "disable") !== null) heldAwake = true
    } else if (!wantAwake && heldAwake) {
      if (ask("idle", "enable") === null) unanswered = true
      else heldAwake = false
    }

    // The shell's services may come up after Ripe does.
    if (unanswered && syncTries < 8) {
      syncTries++
      syncRetry.restart()
    } else {
      syncTries = 0
    }
  }

  onWantDndChanged: syncSession()
  onWantAwakeChanged: syncSession()
  onHeldDndChanged: saveState()
  onHeldAwakeChanged: saveState()

  Timer {
    id: syncRetry
    interval: 1500
    onTriggered: root.syncSession()
  }


  // ---- settings mutators
  function update(patch) {
    settings = Model.sanitizeSettings(Object.assign({}, settings, patch))
    saveSettings()
  }

  // The saved length of a phase: what the next session of it will run for.
  // A session already on the clock keeps the length it has.
  function setMinutes(key, minutes) {
    if (Model.PHASES.indexOf(key) < 0) return
    var patch = {}
    patch[key] = minutes
    update(patch)
  }

  // Lengthen or shorten the session on the clock, this once.
  function extend(minutes) {
    applyTimer(Model.adjust(timer(), Number(minutes) * 60000, Date.now()))
  }

  // Every length control in the panel: at rest it sets the saved length,
  // and during a session it moves that session only.
  function setLength(minutes) {
    if (idle) setMinutes(phase, minutes)
    else extend(Model.clampInt(minutes, phase) - plannedMs / 60000)
  }

  function nudge(minutes) {
    if (idle) setMinutes(phase, Number(settings[phase]) + minutes)
    else extend(minutes)
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

  // ---- saved mixes
  readonly property int currentMix: Model.currentMix(settings)

  function saveMix(name) {
    update(Model.withMix(settings, name))
  }

  function loadMix(name) {
    update(Model.withMixLoaded(settings, name))
  }

  function deleteMix(name) {
    update(Model.withoutMix(settings, name))
  }

  // Step through the saved mixes, one key press each.
  function nextMix() {
    var mixes = settings.mixes
    if (mixes.length === 0) return
    loadMix(mixes[(currentMix + 1) % mixes.length].name)
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
  // The rules live in Model.js as plain functions; this is the value they
  // work on, and the place their results are acted upon.
  function timer() {
    return { phase: phase, status: status, endsAt: endsAt, remainingMs: pausedMs, plannedMs: plannedMs }
  }

  function applyTimer(next) {
    phase = next.phase
    status = next.status
    endsAt = next.endsAt
    pausedMs = next.remainingMs
    plannedMs = next.plannedMs
    tick()
    syncSession()
    saveState()
  }

  // Wakes just after each whole second, so the clock's seconds turn over
  // evenly instead of whenever a coarser timer happens to land.
  function tick() {
    now = Date.now()
    if (!running) return
    if (now >= endsAt) {
      finish()
      return
    }
    ticker.interval = ((endsAt - now - 1) % 1000) + 6
    ticker.restart()
  }

  function start() {
    if (running) return
    var fresh = idle
    alert = ""
    heldAlert = ""
    if (fresh) muted = false
    applyTimer(Model.begin(timer(), settings, Date.now()))
    if (fresh) started()
  }

  function pause() {
    applyTimer(Model.pause(timer(), Date.now()))
  }

  function toggle() {
    running ? pause() : start()
  }

  // Back to the start of the current phase.
  function reset() {
    alert = ""
    heldAlert = ""
    applyTimer(Model.idleTimer(phase))
  }

  // Jump to a phase, e.g. straight to a break.
  function selectPhase(next) {
    if (Model.PHASES.indexOf(next) < 0 || (next === phase && idle)) return
    alert = ""
    heldAlert = ""
    applyTimer(Model.select(timer(), next))
  }

  // Leave the current phase early and line up the other one.
  function skip() {
    selectPhase(Model.otherPhase(phase))
  }

  // The phase ran out.
  function finish() {
    var result = Model.finish(timer(), settings, Date.now())
    if (result.auto) muted = false
    applyTimer(result.timer)
    finished(result.finished)
    if (settings.chime) Quickshell.execDetached(["pw-play", "--volume", "0.6", pluginDir + "/chime.wav"])
    if (!settings.overlay) {
      announce(result.finished)
    } else if (screenLocked()) {
      // The screen would come up over the lock screen and take its keys;
      // it waits until the desktop is back.
      heldAlertMinutes = result.minutes
      heldAlert = result.finished
    } else {
      alertMinutes = result.minutes
      alert = result.finished
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.heldAlert !== ""
    onTriggered: {
      if (root.screenLocked()) return
      root.alertMinutes = root.heldAlertMinutes
      root.alert = root.heldAlert
      root.heldAlert = ""
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
    if (!running) start()
  }

  // Not done yet: a few more minutes of the phase that just ended.
  function extendAlert(minutes) {
    var kind = alert
    if (kind === "") return
    alert = ""
    muted = false
    applyTimer(Model.begin(Model.idleTimer(kind), settings, Date.now(), Math.max(1, minutes) * 60000))
  }

  // After focus: no break, straight back to work.
  function declineAlert() {
    var kind = alert
    alert = ""
    if (kind !== "focus") return
    applyTimer(Model.idleTimer("focus"))
  }

  function notify(title, body) {
    Quickshell.execDetached(["notify-send", "-a", "Ripe", "-i", pluginDir + "/tomato.svg", "-t", "8000", title, body])
  }

  // The fallback when the full-screen message is turned off.
  function announce(finished) {
    var title = finished === "focus" ? strings.t("alert.focus.title") : strings.t("alert.break.title")
    var body = (finished === "focus" ? strings.t("alert.focus.body") : strings.t("alert.break.body"))
      .arg(I18n.formatNumber(Number(settings[phase]), 0))
    notify(title, body)
  }

  // A session ran out while the shell was not running (a restart, a crash,
  // a reboot). It is too late to ring, but not to say so.
  function announceMissed(missed) {
    var when = new Date(missed.endedAt).toLocaleTimeString(Qt.locale(I18n.formatLocale), Locale.ShortFormat)
    notify(strings.t("missed.title"),
      strings.tn("missed." + missed.phase, missed.minutes).arg(I18n.formatNumber(missed.minutes, 0)).arg(when))
  }

  function statusJson() {
    return JSON.stringify({
      phase: phase,
      status: status,
      remaining: Math.ceil(remainingMs / 1000),
      minutes: sessionMinutes,
      alert: alert,
      sounds: audible,
      mix: activeSounds,
      volume: Math.round(settings.master * 100),
      quiet: wantDnd,
      awake: wantAwake
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
      plannedMs: plannedMs,
      heldDnd: heldDnd,
      heldAwake: heldAwake
    }) + "\n")
  }

  function applySettings(text) {
    var parsed = {}
    try { parsed = JSON.parse(text) } catch (e) { parsed = {} }
    settings = Model.sanitizeSettings(parsed)
    settingsLoaded = true
    syncSession()
  }

  function applyState(text) {
    var parsed = {}
    try { parsed = JSON.parse(text) } catch (e) { parsed = {} }
    var held = Model.sanitizeState(parsed)
    var restored = Model.restore(parsed, Date.now())
    heldDnd = held.heldDnd
    heldAwake = held.heldAwake
    stateLoaded = true
    applyTimer(restored.timer)
    if (restored.missed) announceMissed(restored.missed)
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
    id: ticker
    onTriggered: root.tick()
  }

  // One looping player per sound in the mix, alive only while it is heard
  // or fading away, so a silent Ripe holds no audio stream open.
  Instantiator {
    model: Model.SOUNDS
    delegate: Loader {
      id: slot
      required property string modelData
      readonly property bool wanted: root.audible && root.soundActive(modelData)
      // Outlives `wanted` by the length of the fade-out.
      property bool alive: false
      onWantedChanged: {
        if (wanted) alive = true
        // Dropped before it was ever heard: there is no fade to wait for.
        else if (!item || item.gain === 0) alive = false
      }
      Component.onCompleted: if (wanted) alive = true
      function release() { if (!wanted) alive = false }

      active: alive
      sourceComponent: Item {
        id: voice
        // Fades in, so a sound joining the mix does not land at full volume,
        // and out, so the end of a session is not a cut.
        property real gain: 0
        Behavior on gain {
          NumberAnimation { duration: Style.duration(slot.wanted ? 600 : 900); easing.type: Easing.OutCubic }
        }
        onGainChanged: if (gain === 0) Qt.callLater(slot.release)
        Component.onCompleted: {
          gain = Qt.binding(function() { return slot.wanted ? 1 : 0 })
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
