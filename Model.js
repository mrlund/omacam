.pragma library

var DEFAULTS = {
  inputDevice: "auto",
  mode4k: true,
  zoom: 30,
  moveUp: 30,
  moveRight: 100,
  outputWidth: 1920,
  outputHeight: 1080,
  framerate: 30,
  scaler: "lanczos"
}

function even(n) {
  n = Math.floor(Number(n) || 0)
  if (n % 2 !== 0) n -= 1
  return n
}

function clamp(n, min, max) {
  n = Number(n)
  if (!isFinite(n)) n = min
  if (n < min) return min
  if (n > max) return max
  return n
}

function baseSize(mode4k) {
  return mode4k ? { w: 3840, h: 2160 } : { w: 1920, h: 1080 }
}

function mergeConfig(raw) {
  var src = raw && typeof raw === "object" ? raw : {}
  var out = {}
  for (var key in DEFAULTS) out[key] = DEFAULTS[key]
  if (src.inputDevice !== undefined && src.inputDevice !== null && String(src.inputDevice) !== "")
    out.inputDevice = String(src.inputDevice)
  if (src.mode4k !== undefined) out.mode4k = src.mode4k === true || src.mode4k === "true"
  if (src.zoom !== undefined) out.zoom = Number(src.zoom)
  if (src.moveUp !== undefined) out.moveUp = Number(src.moveUp)
  if (src.moveRight !== undefined) out.moveRight = Number(src.moveRight)
  if (src.outputWidth !== undefined) out.outputWidth = Number(src.outputWidth)
  if (src.outputHeight !== undefined) out.outputHeight = Number(src.outputHeight)
  if (src.framerate !== undefined) out.framerate = Number(src.framerate)
  if (src.scaler !== undefined && String(src.scaler) !== "") out.scaler = String(src.scaler)
  return normalize(out)
}

function normalize(cfg) {
  var base = baseSize(cfg.mode4k === true)
  cfg.zoom = clamp(Math.round(Number(cfg.zoom) || 0), 0, 80)
  cfg.outputWidth = even(clamp(cfg.outputWidth || 1920, 320, 3840))
  cfg.outputHeight = even(clamp(cfg.outputHeight || 1080, 180, 2160))
  cfg.framerate = clamp(Math.round(Number(cfg.framerate) || 30), 5, 60)
  var view = viewport(base.w, base.h, cfg.zoom, cfg.moveUp, cfg.moveRight)
  cfg.moveRight = view.moveRight
  cfg.moveUp = view.moveUp
  return cfg
}

function viewport(baseW, baseH, zoom, moveUp, moveRight) {
  var factor = 1 - (Number(zoom) || 0) / 100
  if (factor < 0.2) factor = 0.2
  if (factor > 1) factor = 1
  var viewW = even(Math.max(2, Math.min(baseW, Math.floor(baseW * factor))))
  var viewH = even(Math.max(2, Math.min(baseH, Math.floor(baseH * factor))))
  var centerX = even(Math.floor((baseW - viewW) / 2))
  var centerY = even(Math.floor((baseH - viewH) / 2))
  var x = even((Number(moveRight) || 0) + centerX)
  var y = even(centerY - (Number(moveUp) || 0))
  if (x < 0) x = 0
  if (y < 0) y = 0
  if (x + viewW > baseW) x = even(baseW - viewW)
  if (y + viewH > baseH) y = even(baseH - viewH)
  if (x < 0) x = 0
  if (y < 0) y = 0
  return {
    w: viewW,
    h: viewH,
    x: x,
    y: y,
    moveRight: x - centerX,
    moveUp: centerY - y,
    maxMoveRight: centerX,
    maxMoveUp: centerY
  }
}

function fromRect(baseW, baseH, x, y, w, h) {
  w = even(clamp(w, 2, baseW))
  h = even(Math.round(w * baseH / baseW))
  if (h > baseH) {
    h = even(baseH)
    w = even(Math.round(h * baseW / baseH))
  }
  if (w < 2) w = 2
  if (h < 2) h = 2
  x = even(x)
  y = even(y)
  if (x < 0) x = 0
  if (y < 0) y = 0
  if (x + w > baseW) x = even(baseW - w)
  if (y + h > baseH) y = even(baseH - h)
  var zoom = Math.round((1 - (w / baseW)) * 100)
  if (zoom < 0) zoom = 0
  if (zoom > 80) zoom = 80
  var centerX = Math.floor((baseW - w) / 2)
  var centerY = Math.floor((baseH - h) / 2)
  return normalize({
    mode4k: baseW >= 3000,
    zoom: zoom,
    moveRight: x - centerX,
    moveUp: centerY - y
  })
}

function parseJson(text, fallback) {
  try {
    var parsed = JSON.parse(String(text || ""))
    if (parsed && typeof parsed === "object") return parsed
  } catch (e) {
  }
  return fallback
}

function previewRect(stageW, stageH, imageW, imageH) {
  if (stageW <= 0 || stageH <= 0 || imageW <= 0 || imageH <= 0)
    return { x: 0, y: 0, w: 0, h: 0 }
  var scale = Math.min(stageW / imageW, stageH / imageH)
  var w = imageW * scale
  var h = imageH * scale
  return { x: (stageW - w) / 2, y: (stageH - h) / 2, w: w, h: h }
}

function sourceToPreview(px, py, paint, sourceW, sourceH) {
  if (!paint || paint.w <= 0 || paint.h <= 0 || sourceW <= 0 || sourceH <= 0)
    return { x: 0, y: 0 }
  return {
    x: paint.x + (px / sourceW) * paint.w,
    y: paint.y + (py / sourceH) * paint.h
  }
}

function previewToSource(px, py, paint, sourceW, sourceH) {
  if (!paint || paint.w <= 0 || paint.h <= 0 || sourceW <= 0 || sourceH <= 0)
    return { x: 0, y: 0 }
  return {
    x: ((px - paint.x) / paint.w) * sourceW,
    y: ((py - paint.y) / paint.h) * sourceH
  }
}

function elide(text, max) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  if (value.length <= max) return value
  return value.substring(0, Math.max(0, max - 1)) + "…"
}
