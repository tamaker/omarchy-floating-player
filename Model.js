.pragma library

// Pure helpers for Widget.qml (no QML state). Kept separate so the parsing
// rules are easy to read and to test with plain node.

var SOURCES = ["youtube", "youtubetv"]
var SIZES = ["small", "medium", "large", "full"]
var CORNERS = ["tl", "tr", "bl", "br"]

var SOURCE_LABELS = { youtube: "YouTube", youtubetv: "YouTube TV" }
var SIZE_LABELS = { small: "Small", medium: "Medium", large: "Large", full: "Fullscreen" }
var CORNER_LABELS = { tl: "top left", tr: "top right", bl: "bottom left", br: "bottom right" }

// Window opacity in percent; the CLI clamps to the same range.
var OPACITY_MIN = 20
var OPACITY_MAX = 100

function notRunning() {
  return { running: false, visible: false, source: "", size: "", corner: "", opacity: OPACITY_MAX }
}

function opacityPercent(value) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return OPACITY_MAX
  return Math.max(OPACITY_MIN, Math.min(OPACITY_MAX, n))
}

function oneOf(value, allowed) {
  var s = String(value === undefined || value === null ? "" : value)
  return allowed.indexOf(s) >= 0 ? s : ""
}

// `floating-player status` prints one JSON line. Anything else (missing
// script, error text, partial output) means "not running". Only the last
// non-empty line is parsed, so a stray warning on stdout doesn't break it.
function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (!text) return notRunning()
  var lines = text.split("\n")
  var obj
  try { obj = JSON.parse(lines[lines.length - 1]) } catch (e) { return notRunning() }
  if (obj === null || typeof obj !== "object" || Array.isArray(obj)) return notRunning()
  var running = obj.running === true
  return {
    running: running,
    visible: running && obj.visible === true,
    // A source is any short identifier (a raw URL open may report its own);
    // size/corner are restricted to the values the UI knows how to highlight.
    source: typeof obj.source === "string" ? obj.source.slice(0, 64) : "",
    size: oneOf(obj.size, SIZES),
    corner: oneOf(obj.corner, CORNERS),
    opacity: opacityPercent(obj.opacity)
  }
}

// `floating-player signin --check` -> {"youtube":bool|null,"youtubetv":bool|null}.
// Returns {source: true|false|null}; null = unknown (missing, failed, garbage).
function parseSignin(raw) {
  var out = {}
  for (var i = 0; i < SOURCES.length; i++) out[SOURCES[i]] = null
  var text = String(raw || "").trim()
  if (!text) return out
  var lines = text.split("\n")
  var obj
  try { obj = JSON.parse(lines[lines.length - 1]) } catch (e) { return out }
  if (obj === null || typeof obj !== "object" || Array.isArray(obj)) return out
  for (var j = 0; j < SOURCES.length; j++) {
    var v = obj[SOURCES[j]]
    out[SOURCES[j]] = v === true ? true : (v === false ? false : null)
  }
  return out
}

// Only a single http(s) URL with no whitespace is accepted from the clipboard.
function clipboardUrl(raw) {
  var text = String(raw || "").trim()
  if (text.length === 0 || text.length > 4096) return ""
  return /^https?:\/\/[^\s]+$/i.test(text) ? text : ""
}

function sourceLabel(source) {
  if (SOURCE_LABELS[source]) return SOURCE_LABELS[source]
  return source ? String(source) : ""
}

// Short state line for the tooltip and the popup header.
function stateText(status, cliMissing) {
  if (cliMissing) return "floating-player CLI not found"
  if (!status || !status.running) return "Not running"
  var parts = [status.visible ? "Showing" : "Hidden"]
  if (status.source) parts.push(sourceLabel(status.source))
  if (status.size) parts.push(SIZE_LABELS[status.size].toLowerCase())
  if (status.corner && status.size !== "full") parts.push(CORNER_LABELS[status.corner])
  return parts.join(" · ")
}

// Popup header: just visibility + source (size/corner are shown as chips).
function headerText(status, cliMissing) {
  if (cliMissing || !status || !status.running) return stateText(status, cliMissing)
  var parts = [status.visible ? "Showing" : "Hidden"]
  if (status.source) parts.push(sourceLabel(status.source))
  return parts.join(" · ")
}

function normalizedSetting(value, allowed, fallback) {
  var s = oneOf(value, allowed)
  return s !== "" ? s : fallback
}
