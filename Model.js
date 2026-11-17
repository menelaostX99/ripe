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
  master: 0.6,
  active: [],
  levels: {}
}

var LIMITS = {
  focus: [1, 180],
  "break": [1, 60]
}

var PRESETS = {
  focus: [15, 25, 45, 60, 90],
  "break": [5, 10, 15, 20, 30]
}

var FLAGS = ["autoBreaks", "autoFocus", "soundsWithFocus", "chime", "overlay"]

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
  out.active = []
  if (Array.isArray(src.active)) {
    for (var a = 0; a < src.active.length; a++)
      if (SOUNDS.indexOf(src.active[a]) >= 0 && out.active.indexOf(src.active[a]) < 0) out.active.push(src.active[a])
  }
  out.levels = {}
  if (src.levels && typeof src.levels === "object") {
    for (var s = 0; s < SOUNDS.length; s++) {
      var level = Number(src.levels[SOUNDS[s]])
      if (isFinite(level)) out.levels[SOUNDS[s]] = clamp(level, 0.05, 1)
    }
  }
  return out
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
    remainingMs: isFinite(remainingMs) ? clamp(remainingMs, 0, 180 * 60000) : 0,
    plannedMs: isFinite(plannedMs) ? clamp(plannedMs, 0, 180 * 60000) : 0
  }
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
