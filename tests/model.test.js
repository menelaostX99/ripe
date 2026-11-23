// node tests/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(".pragma library", "")
const names = ["SOUNDS", "PHASES", "DEFAULTS", "LIMITS", "FLAGS", "MAX_MIXES", "sanitizeSettings", "sanitizeState", "clock",
  "otherPhase", "idleTimer", "remaining", "begin", "pause", "select", "adjust", "finish", "restore", "withMix", "withoutMix",
  "withMixLoaded", "currentMix", "mixName", "clockCells", "clockTemplate"]
const Model = new Function(source + "; return { " + names.join(", ") + " }")()

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

// ---- the timer
const MIN = 60000
const settings = Model.sanitizeSettings({ focus: 25, break: 5 })
const t0 = 1000000

// Start, pause, resume: the remaining time is carried, the plan is kept.
let timer = Model.begin(Model.idleTimer("focus"), settings, t0)
assert.strictEqual(timer.status, "running")
assert.strictEqual(timer.endsAt, t0 + 25 * MIN)
assert.strictEqual(timer.plannedMs, 25 * MIN)
assert.strictEqual(Model.begin(timer, settings, t0 + 5), timer)
timer = Model.pause(timer, t0 + 10 * MIN)
assert.strictEqual(timer.status, "paused")
assert.strictEqual(timer.remainingMs, 15 * MIN)
assert.strictEqual(Model.remaining(timer, settings, t0 + 99 * MIN), 15 * MIN)
timer = Model.begin(timer, settings, t0 + 20 * MIN)
assert.strictEqual(timer.endsAt, t0 + 35 * MIN)
assert.strictEqual(timer.plannedMs, 25 * MIN)
assert.strictEqual(Model.remaining(Model.idleTimer("break"), settings, t0), 5 * MIN)

// "+5" moves this session and nothing else.
const before = JSON.stringify(settings)
timer = Model.adjust(timer, 5 * MIN, t0 + 20 * MIN)
assert.strictEqual(timer.endsAt, t0 + 40 * MIN)
assert.strictEqual(timer.plannedMs, 30 * MIN)
assert.strictEqual(JSON.stringify(settings), before)
// Taking off more than is left stops a second short of the end, not past it.
assert.strictEqual(Model.adjust(timer, -90 * MIN, t0 + 20 * MIN).endsAt, t0 + 20 * MIN + 1000)
// A paused session moves too; an idle one has nothing to move.
const held = Model.adjust(Model.pause(timer, t0 + 30 * MIN), -5 * MIN, t0 + 31 * MIN)
assert.strictEqual(held.remainingMs, 5 * MIN)
assert.strictEqual(held.plannedMs, 25 * MIN)
assert.strictEqual(Model.adjust(Model.idleTimer("focus"), 5 * MIN, t0).status, "idle")
// A session cannot be stretched past three hours.
assert.strictEqual(Model.adjust(timer, 999 * MIN, t0 + 20 * MIN).endsAt, t0 + 20 * MIN + 180 * MIN)

// The end of a phase lines up the other one, started or not as asked.
let done = Model.finish(timer, settings, t0 + 40 * MIN)
assert.strictEqual(done.finished, "focus")
assert.strictEqual(done.minutes, 30)
assert.strictEqual(done.auto, true)
assert.strictEqual(done.timer.phase, "break")
assert.strictEqual(done.timer.status, "running")
assert.strictEqual(done.timer.endsAt, t0 + 45 * MIN)
done = Model.finish(done.timer, settings, t0 + 45 * MIN)
assert.strictEqual(done.finished, "break")
assert.strictEqual(done.auto, false)
assert.strictEqual(done.timer.status, "idle")
assert.strictEqual(done.timer.phase, "focus")

// Jumping phase drops the session; picking the idle phase again is a no-op.
assert.strictEqual(Model.select(timer, "break").status, "idle")
assert.strictEqual(Model.select(timer, "nap"), timer)
const resting = Model.idleTimer("focus")
assert.strictEqual(Model.select(resting, "focus"), resting)

// A session that ended while the shell was down is reported, not replayed.
const saved = { phase: "focus", status: "running", endsAt: t0 + 50 * MIN, plannedMs: 50 * MIN }
let back = Model.restore(saved, t0 + 20 * MIN)
assert.strictEqual(back.missed, null)
assert.strictEqual(back.timer.status, "running")
back = Model.restore(saved, t0 + 90 * MIN)
assert.deepStrictEqual(back.missed, { phase: "focus", minutes: 50, endedAt: t0 + 50 * MIN })
assert.strictEqual(back.timer.phase, "break")
assert.strictEqual(back.timer.status, "idle")
assert.strictEqual(Model.restore({ phase: "break", status: "paused", remainingMs: 2 * MIN }, t0).missed, null)
assert.strictEqual(Model.restore("junk", t0).timer.status, "idle")
assert.strictEqual(Model.sanitizeState({ heldDnd: true, heldAwake: "yes" }).heldDnd, true)
assert.strictEqual(Model.sanitizeState({ heldDnd: true, heldAwake: "yes" }).heldAwake, false)

// ---- saved mixes
let mixed = Model.sanitizeSettings({ active: ["rain", "fireplace"], levels: { rain: 0.4, wind: 0.9 } })
mixed = Model.withMix(mixed, "  Rainy   café ")
assert.deepStrictEqual(mixed.mixes, [{ name: "Rainy café", active: ["rain", "fireplace"], levels: { rain: 0.4, fireplace: 0.6 } }])
assert.strictEqual(Model.currentMix(mixed), 0)
// The same name, in any case, replaces instead of piling up.
mixed = Model.withMix(Object.assign({}, mixed, { active: ["rain"] }), "rainy CAFÉ")
assert.strictEqual(mixed.mixes.length, 1)
assert.deepStrictEqual(mixed.mixes[0].active, ["rain"])
// Loading a mix restores its sounds and keeps other sounds' levels.
let loaded = Model.withMixLoaded(Object.assign({}, mixed, { active: ["wind"], levels: { wind: 0.9, rain: 1 } }), "Rainy café")
assert.deepStrictEqual(loaded.active, ["rain"])
assert.deepStrictEqual(loaded.levels, { wind: 0.9, rain: 0.4 })
assert.strictEqual(Model.currentMix(Object.assign({}, loaded, { levels: { rain: 0.8 } })), -1)
assert.strictEqual(Model.withoutMix(mixed, "RAINY café").mixes.length, 0)
// Nothing picked, or no name: nothing saved.
assert.strictEqual(Model.withMix(Model.sanitizeSettings({}), "Empty").mixes.length, 0)
assert.strictEqual(Model.withMix(mixed, "   ").mixes.length, 1)
// Mixes from disk are untrusted: bounded, deduplicated, and stripped.
const many = []
for (let i = 0; i < 20; i++) many.push({ name: "Mix " + i, active: ["rain"] })
assert.strictEqual(Model.sanitizeSettings({ mixes: many }).mixes.length, Model.MAX_MIXES)
const rough = Model.sanitizeSettings({ mixes: [
  { name: "<img src=x>\n" + "y".repeat(80), active: ["rain", "<b>"], levels: { rain: 7 } },
  { name: "none", active: [] }, { name: 4, active: ["rain"] }, null,
  { name: "A", active: ["rain"] }, { name: "a", active: ["wind"] }
] }).mixes
assert.strictEqual(rough.length, 2)
assert.strictEqual(rough[0].name.length, 24)
assert.ok(rough[0].name.indexOf("\n") < 0)
assert.deepStrictEqual(rough[0].active, ["rain"])
assert.deepStrictEqual(rough[0].levels, { rain: 1 })
assert.strictEqual(rough[1].name, "A")
// The new options are off until asked for.
assert.strictEqual(Model.sanitizeSettings({}).focusDnd, false)
assert.strictEqual(Model.sanitizeSettings({ keepAwake: true, focusDnd: "yes" }).keepAwake, true)
assert.strictEqual(Model.sanitizeSettings({ keepAwake: true, focusDnd: "yes" }).focusDnd, false)

// ---- drawing helpers
assert.deepStrictEqual(Model.clockCells("1:04:59"), ["1", ":", "0", "4", ":", "5", "9"])
assert.strictEqual(Model.clockTemplate("24:59"), "00:00")

console.log("model: ok")
