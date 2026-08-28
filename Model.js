// Pure transformation logic and helper functions for susamn.rclone plugin

function parseJson(text, fallback) {
  try {
    var trimmed = String(text === undefined || text === null ? "" : text).trim()
    if (trimmed === "") return fallback
    return JSON.parse(trimmed)
  } catch (e) {
    return fallback
  }
}

function emptyStatus() {
  return {
    installed: false,
    is_sync_running: false,
    active_processes_count: 0,
    total_speed_bps: 0,
    total_bandwidth_bps: 0,
    processes: [],
    remotes_count: 0,
    remotes: [],
    mounts_count: 0,
    mounts: [],
    timers_count: 0,
    timers: [],
    next_timer: null,
    history: [],
    timestamp: 0
  }
}

function barTooltipText(status) {
  if (!status || !status.installed) {
    return "Rclone: Not found on PATH"
  }
  if (status.is_sync_running) {
    var procs = (status.processes && status.processes.length) ? status.processes : []
    var count = procs.filter(function(p) {
      return p.is_transfer === true
        || p.operation === "sync" || p.operation === "bisync"
        || p.operation === "copy" || p.operation === "move"
    }).length
    var label = "Rclone: " + count + " transfer" + (count === 1 ? "" : "s") + " running"
    var rate = Number(status.total_speed_bps) || 0
    return rate > 0 ? label + " · " + formatRate(rate) : label
  }
  if (status.next_timer && status.next_timer.next_formatted) {
    var prof = status.next_timer.profile || "job"
    return "Rclone: Next " + prof + " " + status.next_timer.next_formatted
  }
  if (status.remotes_count > 0) {
    return "Rclone: " + status.remotes_count + " remote" + (status.remotes_count > 1 ? "s" : "") + " configured"
  }
  return "Rclone: Idle"
}

// Human label for a transfer's direction/kind. Accepts rclone subcommands
// (sync, bisync, copy, move, check) and the values status.py derives from
// sync profiles (one, two, one-way, bi, ...).
function syncKindLabel(kind) {
  var k = String(kind || "").toLowerCase()
  if (k === "bisync" || k === "bi" || k === "two" || k === "bidirectional" || k === "two-way") return "bi-directional"
  if (k === "sync" || k === "one" || k === "oneway" || k === "one-way") return "one-way sync"
  if (k === "copy") return "copy"
  if (k === "move") return "move"
  if (k === "check") return "check"
  if (k === "mount") return "mount"
  if (k === "cron") return "cron job"
  return k || "sync"
}

function operationIcon(op) {
  var o = String(op || "").toLowerCase()
  if (o === "sync") return "󰑮"
  if (o === "bisync") return "󰁯"
  if (o === "copy") return "󰆏"
  if (o === "move") return "󰪹"
  if (o === "mount") return "󱡶"
  if (o === "check") return "󰄬"
  if (o === "daemon") return "󰒋"
  return "󰜱"
}

function formatPercent(val) {
  var num = Number(val || 0)
  if (isNaN(num) || num < 0) return 0
  if (num > 100) return 100
  return Math.round(num * 10) / 10
}

function clamp(val, min, max) {
  return Math.max(min, Math.min(max, val))
}

function formatBytes(bytes) {
  var v = Number(bytes)
  if (!isFinite(v) || v < 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024
    i++
  }
  return (i === 0 ? Math.round(v) : Math.round(v * 10) / 10) + " " + units[i]
}

// Per-second throughput label, e.g. "4.2 MB/s". Used for the speed-graph
// peak readout; per-process figures are formatted by status.py.
function formatRate(bytesPerSec) {
  return formatBytes(bytesPerSec) + "/s"
}

function calculateTimelineX(hourFloat, totalWidth) {
  if (hourFloat === undefined || hourFloat === null || hourFloat < 0) return -1
  var clamped = clamp(Number(hourFloat), 0, 24)
  return Math.round((clamped / 24.0) * totalWidth)
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseJson: parseJson,
    emptyStatus: emptyStatus,
    barTooltipText: barTooltipText,
    operationIcon: operationIcon,
    syncKindLabel: syncKindLabel,
    formatPercent: formatPercent,
    clamp: clamp,
    calculateTimelineX: calculateTimelineX,
    formatBytes: formatBytes,
    formatRate: formatRate
  }
}
