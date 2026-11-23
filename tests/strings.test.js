// node tests/strings.test.js
// Every catalog is valid JSON, translates only keys English has, keeps each
// %1 and %2 placeholder, and gives every plural entry an "other" form.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const dir = path.join(__dirname, "..", "i18n")
const read = file => JSON.parse(fs.readFileSync(path.join(dir, file), "utf8"))
const en = read("en.json")
const holders = value => ["%1", "%2"].filter(p => JSON.stringify(value).includes(p)).join()

for (const file of fs.readdirSync(dir).filter(f => f.endsWith(".json") && f !== "en.json")) {
  const catalog = read(file)
  for (const key of Object.keys(catalog)) {
    assert.ok(key in en, `${file}: ${key} is not in en.json`)
    assert.strictEqual(holders(catalog[key]), holders(en[key]), `${file}: ${key} placeholders`)
    if (typeof catalog[key] === "object") assert.strictEqual(typeof catalog[key].other, "string", `${file}: ${key} needs "other"`)
    else assert.ok(typeof catalog[key] === "string" && catalog[key].length > 0, `${file}: ${key} is empty`)
  }
}
for (const key of Object.keys(en))
  if (typeof en[key] === "object") assert.strictEqual(typeof en[key].other, "string", `en.json: ${key} needs "other"`)

console.log("strings: ok")
