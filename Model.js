.pragma library

// Pure helpers for the Ripe store and panel: no QML, no I/O, so the same
// file runs under node for tests (see tests/model.test.js).

// Blanket's bundled sounds, in the order Blanket lists them. The id is the
// file name inside blanket.gresource; the label is the i18n key suffix.
var SOUNDS = [
  "rain", "storm", "wind", "waves", "stream", "birds", "summer-night",
  "fireplace", "coffee-shop", "city", "train", "boat", "white-noise", "pink-noise"
]

var PHASES = ["focus", "break"]

var DEFAULTS = {
  focus: 25,
  "break": 5,
  autoBreaks: true,
  autoFocus: false,
  chime: true,
  overlay: true,
  soundsWithFocus: true,
  focusDnd: false,
  keepAwake: false,
  master: 0.6,
  active: [],
  levels: {},
  mixes: []
}

var LIMITS = {
  focus: [1, 180],
  "break": [1, 60]
}

var PRESETS = {
  focus: [15, 25, 45, 60, 90],
  "break": [5, 10, 15, 20, 30]
}

var FLAGS = ["autoBreaks", "autoFocus", "soundsWithFocus", "focusDnd", "keepAwake", "chime", "overlay"]

// Saved mixes: how many, and how long a name may be.
var MAX_MIXES = 8
var MAX_MIX_NAME = 24

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

function clampInt(value, key) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) n = DEFAULTS[key]
  return clamp(n, LIMITS[key][0], LIMITS[key][1])
}

// Settings read from disk are untrusted: keep known keys, coerce types, and
// drop anything else.
function sanitizeSettings(raw) {
  var src = raw && typeof raw === "object" ? raw : {}
  var out = {}
  for (var key in LIMITS) out[key] = clampInt(src[key] === undefined ? DEFAULTS[key] : src[key], key)
  // The break length was called "short" before long breaks were dropped.
  if (src["break"] === undefined && src["short"] !== undefined) out["break"] = clampInt(src["short"], "break")
  for (var i = 0; i < FLAGS.length; i++)
    out[FLAGS[i]] = typeof src[FLAGS[i]] === "boolean" ? src[FLAGS[i]] : DEFAULTS[FLAGS[i]]
  var master = Number(src.master)
  out.master = isFinite(master) ? clamp(master, 0, 1) : DEFAULTS.master
  out.active = sanitizeActive(src.active)
  out.levels = sanitizeLevels(src.levels)
  out.mixes = []
  if (Array.isArray(src.mixes)) {
    for (var m = 0; m < src.mixes.length && out.mixes.length < MAX_MIXES; m++) {
      var mix = sanitizeMix(src.mixes[m])
      if (mix && mixIndex(out.mixes, mix.name) < 0) out.mixes.push(mix)
    }
  }
  return out
}

function sanitizeActive(raw) {
  var out = []
  if (!Array.isArray(raw)) return out
  for (var a = 0; a < raw.length; a++)
    if (SOUNDS.indexOf(raw[a]) >= 0 && out.indexOf(raw[a]) < 0) out.push(raw[a])
  return out
}

function sanitizeLevels(raw) {
  var out = {}
  if (!raw || typeof raw !== "object") return out
  for (var s = 0; s < SOUNDS.length; s++) {
    var level = Number(raw[SOUNDS[s]])
    if (isFinite(level)) out[SOUNDS[s]] = clamp(level, 0.05, 1)
  }
  return out
}

// A name is shown as plain text and matched without regard to case; control
// characters and surrounding space are dropped.
function mixName(raw) {
  if (typeof raw !== "string") return ""
  return raw.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, MAX_MIX_NAME).trim()
}

// A saved mix holds only the sounds that are in it, each with its level.
function sanitizeMix(raw) {
  if (!raw || typeof raw !== "object") return null
  var name = mixName(raw.name)
  var active = sanitizeActive(raw.active)
  if (name === "" || active.length === 0) return null
  var all = sanitizeLevels(raw.levels)
  var levels = {}
  for (var i = 0; i < active.length; i++) levels[active[i]] = all[active[i]] === undefined ? 0.6 : all[active[i]]
  return { name: name, active: active, levels: levels }
}

function mixIndex(mixes, name) {
  var wanted = mixName(name).toLowerCase()
  for (var i = 0; i < mixes.length; i++)
    if (mixes[i].name.toLowerCase() === wanted) return i
  return -1
}

// The saved mix that matches what is picked right now, or -1.
function currentMix(settings) {
  var active = settings.active.slice().sort().join(",")
  for (var i = 0; i < settings.mixes.length; i++) {
    var mix = settings.mixes[i]
    if (mix.active.slice().sort().join(",") !== active) continue
    var same = true
    for (var a = 0; a < mix.active.length; a++) {
      var level = settings.levels[mix.active[a]]
      if (Math.abs((level === undefined ? 0.6 : level) - mix.levels[mix.active[a]]) > 0.005) same = false
    }
    if (same) return i
  }
  return -1
}

// Settings with the current selection saved under `name`, replacing a mix
// of the same name. Unchanged when there is nothing to save or no room.
function withMix(settings, name) {
  var mix = sanitizeMix({ name: name, active: settings.active, levels: settings.levels })
  if (!mix) return settings
  var mixes = settings.mixes.slice()
  var at = mixIndex(mixes, mix.name)
  if (at >= 0) mixes[at] = mix
  else if (mixes.length < MAX_MIXES) mixes.push(mix)
  else return settings
  return Object.assign({}, settings, { mixes: mixes })
}

function withoutMix(settings, name) {
  var at = mixIndex(settings.mixes, name)
  if (at < 0) return settings
  var mixes = settings.mixes.slice()
  mixes.splice(at, 1)
  return Object.assign({}, settings, { mixes: mixes })
}

// Settings with a saved mix made the current selection. Levels of sounds
// outside the mix are kept, so they come back where they were left.
function withMixLoaded(settings, name) {
  var at = mixIndex(settings.mixes, name)
  if (at < 0) return settings
  var mix = settings.mixes[at]
  return Object.assign({}, settings, {
    active: mix.active.slice(),
    levels: Object.assign({}, settings.levels, mix.levels)
  })
}

function sanitizeState(raw) {
  var src = raw && typeof raw === "object" ? raw : {}
  var endsAt = Number(src.endsAt)
  var remainingMs = Number(src.remainingMs)
  var plannedMs = Number(src.plannedMs)
  return {
    phase: PHASES.indexOf(src.phase) >= 0 ? src.phase : "focus",
    status: ["idle", "running", "paused"].indexOf(src.status) >= 0 ? src.status : "idle",
    endsAt: isFinite(endsAt) ? endsAt : 0,
    remainingMs: isFinite(remainingMs) ? clamp(remainingMs, 0, MAX_SESSION_MS) : 0,
    plannedMs: isFinite(plannedMs) ? clamp(plannedMs, 0, MAX_SESSION_MS) : 0,
    // What Ripe switched on for the session and still has to hand back.
    heldDnd: src.heldDnd === true,
    heldAwake: src.heldAwake === true
  }
}

// ---- the timer
//
// The timer is a plain value, { phase, status, endsAt, remainingMs,
// plannedMs }, and every change to it is a function from the old value (and
// the time, passed in) to a new one. RipeStore.qml holds the value and does
// the things these functions only describe: ringing, saving, showing.

var MAX_SESSION_MS = 180 * 60000
// A running session is never adjusted to less than this.
var MIN_LEFT_MS = 1000

function idleTimer(phase) {
  return { phase: PHASES.indexOf(phase) >= 0 ? phase : "focus", status: "idle", endsAt: 0, remainingMs: 0, plannedMs: 0 }
}

function copyTimer(timer, patch) {
  return Object.assign({ phase: timer.phase, status: timer.status, endsAt: timer.endsAt,
    remainingMs: timer.remainingMs, plannedMs: timer.plannedMs }, patch)
}

function phaseMs(settings, phase) {
  return Number(settings[phase]) * 60000
}

// What is left on the clock at `now`.
function remaining(timer, settings, now) {
  if (timer.status === "running") return Math.max(0, timer.endsAt - now)
  if (timer.status === "paused") return timer.remainingMs
  return phaseMs(settings, timer.phase)
}

// Start the current phase, or pick a paused one back up. `ms` forces a fresh
// run of that length, whatever the timer was doing.
function begin(timer, settings, now, ms) {
  if (timer.status === "running" && ms === undefined) return timer
  var resume = timer.status === "paused" && ms === undefined
  var left = resume ? timer.remainingMs : (ms === undefined ? phaseMs(settings, timer.phase) : ms)
  return copyTimer(timer, {
    status: "running",
    endsAt: now + left,
    remainingMs: 0,
    plannedMs: resume ? timer.plannedMs : left
  })
}

function pause(timer, now) {
  if (timer.status !== "running") return timer
  return copyTimer(timer, { status: "paused", remainingMs: Math.max(0, timer.endsAt - now), endsAt: 0 })
}

function select(timer, phase) {
  if (PHASES.indexOf(phase) < 0) return timer
  if (phase === timer.phase && timer.status === "idle") return timer
  return idleTimer(phase)
}

// Move the end of the session on the clock by `deltaMs`, for this session
// only: the saved length of the phase is not touched. An idle timer has no
// session to move.
function adjust(timer, deltaMs, now) {
  if (timer.status === "idle" || !isFinite(deltaMs) || deltaMs === 0) return timer
  var left = timer.status === "running" ? timer.endsAt - now : timer.remainingMs
  var next = clamp(left + deltaMs, MIN_LEFT_MS, MAX_SESSION_MS)
  var planned = clamp(timer.plannedMs + (next - left), MIN_LEFT_MS, MAX_SESSION_MS)
  return timer.status === "running"
    ? copyTimer(timer, { endsAt: now + next, plannedMs: planned })
    : copyTimer(timer, { remainingMs: next, plannedMs: planned })
}

// The running phase has reached its end. Returns the timer lined up on the
// other phase (already running when that phase starts by itself), with what
// just finished: { timer, finished, minutes, auto }.
function finish(timer, settings, now) {
  var finished = timer.phase
  var minutes = Math.max(1, Math.round(timer.plannedMs / 60000))
  var next = idleTimer(otherPhase(finished))
  var auto = next.phase === "focus" ? settings.autoFocus === true : settings.autoBreaks === true
  if (auto) next = begin(next, settings, now)
  return { timer: next, finished: finished, minutes: minutes, auto: auto }
}

// A timer read back from disk at `now`. A session whose end passed while
// nothing was watching is over: the other phase is lined up, nothing starts
// by itself, and `missed` says what ended and when.
function restore(raw, now) {
  var state = sanitizeState(raw)
  var timer = { phase: state.phase, status: state.status, endsAt: state.endsAt,
    remainingMs: state.remainingMs, plannedMs: state.plannedMs }
  if (timer.status !== "running" || now < timer.endsAt)
    return { timer: timer, missed: null }
  return {
    timer: idleTimer(otherPhase(timer.phase)),
    missed: { phase: timer.phase, minutes: Math.max(1, Math.round(timer.plannedMs / 60000)), endedAt: timer.endsAt }
  }
}

// ---- small things the panel draws with

// Each digit of a clock as its own cell, so one can change without the rest
// moving: "24:59" is ["2", "4", ":", "5", "9"].
function clockCells(text) {
  return String(text).split("")
}

// The same clock with every digit replaced by 0: the width to reserve.
function clockTemplate(text) {
  return String(text).replace(/[0-9]/g, "0")
}

function pad(n) {
  return n < 10 ? "0" + n : String(n)
}

// "24:59", or "1:04:59" past the hour. Rounds up so a fresh 25 minutes reads
// 25:00 and the last second reads 00:01, not 00:00.
function clock(ms) {
  var total = Math.max(0, Math.ceil(ms / 1000))
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s)
}

function otherPhase(phase) {
  return phase === "focus" ? "break" : "focus"
}
