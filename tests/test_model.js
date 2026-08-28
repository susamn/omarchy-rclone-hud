const assert = require("assert")
const Model = require("../Model.js")

// 1. parseJson
assert.deepStrictEqual(Model.parseJson('{"test": 123}', {}), { test: 123 })
assert.deepStrictEqual(Model.parseJson('', { fallback: true }), { fallback: true })
assert.deepStrictEqual(Model.parseJson('invalid', null), null)

// 2. emptyStatus
const empty = Model.emptyStatus()
assert.strictEqual(empty.installed, false)
assert.strictEqual(empty.is_sync_running, false)
assert.strictEqual(empty.remotes_count, 0)

// 3. barTooltipText
assert.strictEqual(Model.barTooltipText(null), "Rclone: Not found on PATH")
assert.strictEqual(Model.barTooltipText({ installed: false }), "Rclone: Not found on PATH")
assert.strictEqual(Model.barTooltipText({
  installed: true,
  is_sync_running: true,
  processes: [{ operation: "sync", is_transfer: true }]
}), "Rclone: 1 transfer running")
assert.strictEqual(Model.barTooltipText({
  installed: true,
  is_sync_running: true,
  total_speed_bps: 4404019,
  processes: [{ operation: "sync", is_transfer: true }, { operation: "copy", is_transfer: true }]
}), "Rclone: 2 transfers running · 4.2 MB/s")
// A lone mount is not a transfer and must not read as "running".
assert.strictEqual(Model.barTooltipText({
  installed: true,
  is_sync_running: false,
  remotes_count: 2,
  processes: [{ operation: "mount", is_transfer: false }]
}), "Rclone: 2 remotes configured")
assert.strictEqual(Model.barTooltipText({
  installed: true,
  is_sync_running: false,
  next_timer: { profile: "music-tracks", next_formatted: "in 25m" }
}), "Rclone: Next music-tracks in 25m")

// 4. operationIcon
assert.strictEqual(Model.operationIcon("sync"), "󰑮")
assert.strictEqual(Model.operationIcon("bisync"), "󰁯")
assert.strictEqual(Model.operationIcon("mount"), "󱡶")
assert.strictEqual(Model.operationIcon("unknown"), "󰜱")

// 5. formatPercent & calculateTimelineX
assert.strictEqual(Model.formatPercent(12.345), 12.3)
assert.strictEqual(Model.formatPercent(-5), 0)
assert.strictEqual(Model.formatPercent(150), 100)

assert.strictEqual(Model.calculateTimelineX(12.0, 240), 120)
assert.strictEqual(Model.calculateTimelineX(0.0, 240), 0)
assert.strictEqual(Model.calculateTimelineX(24.0, 240), 240)
assert.strictEqual(Model.calculateTimelineX(-1, 240), -1)

console.log("All Model.js unit tests passed successfully!")
