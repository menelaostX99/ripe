// node tests/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(".pragma library", "")
const Model = new Function(source + "; return { SOUNDS, PHASES, DEFAULTS, LIMITS, sanitizeSettings, sanitizeState, clock, otherPhase }")()

// A typed duration survives a round trip instead of snapping back to 25.
assert.strictEqual(Model.sanitizeSettings({ focus: 50 }).focus, 50)
assert.strictEqual(Model.sanitizeSettings(Model.sanitizeSettings({ focus: 42, break: 7 })).focus, 42)
assert.strictEqual(Model.sanitizeSettings(Model.sanitizeSettings({ focus: 42, break: 7 })).break, 7)
assert.strictEqual(Model.sanitizeSettings({ focus: 9999 }).focus, 180)
assert.strictEqual(Model.sanitizeSettings({ focus: "abc" }).focus, 25)
assert.strictEqual(Model.sanitizeSettings(null).break, 5)
assert.strictEqual(Model.sanitizeSettings(null).overlay, true)

// Settings written before long breaks were dropped keep their break length.
assert.strictEqual(Model.sanitizeSettings({ short: 9, long: 20, rounds: 4 }).break, 9)
assert.strictEqual(Model.sanitizeSettings({ short: 9, long: 20 }).long, undefined)

// Untrusted settings: unknown sounds and markup are dropped.
const dirty = Model.sanitizeSettings({ active: ["rain", "<img src=x>", "rain", 7], levels: { rain: 9, "<b>": 1, wind: "x" }, master: -3 })
assert.deepStrictEqual(dirty.active, ["rain"])
assert.deepStrictEqual(dirty.levels, { rain: 1 })
assert.strictEqual(dirty.master, 0)
assert.strictEqual(Model.sanitizeState({ phase: "<script>", status: 4 }).phase, "focus")
assert.strictEqual(Model.sanitizeState({ phase: "long", status: 4 }).status, "idle")
assert.strictEqual(Model.sanitizeState({ phase: "break" }).phase, "break")
assert.strictEqual(Model.sanitizeState({ history: { a: 1 } }).history, undefined)

assert.strictEqual(Model.clock(25 * 60000), "25:00")
assert.strictEqual(Model.clock(999), "00:01")
assert.strictEqual(Model.clock(0), "00:00")
assert.strictEqual(Model.clock(90 * 60000), "1:30:00")
assert.strictEqual(Model.otherPhase("focus"), "break")
assert.strictEqual(Model.otherPhase("break"), "focus")

console.log("model: ok")
