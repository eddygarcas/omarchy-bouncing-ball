var sizePresets = [
  { label: "S", size: 50 },
  { label: "M", size: 90 },
  { label: "L", size: 140 },
  { label: "XL", size: 200 }
]

var speedPresets = [
  { label: "Chill", speed: 140 },
  { label: "Normal", speed: 260 },
  { label: "Fast", speed: 420 },
  { label: "Turbo", speed: 650 }
]

var stylePresets = [
  { label: "Amiga", value: "amiga" },
  { label: "Solid", value: "solid" },
  { label: "Rainbow", value: "rainbow" }
]

var physicsPresets = [
  { label: "Classic bounce", value: "classic" },
  { label: "Gravity drop", value: "gravity" }
]

var colorSwatches = [
  "#e6392b",
  "#e67e22",
  "#f1c40f",
  "#16a085",
  "#2980b9",
  "#8e44ad"
]

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

function randomVelocity(speed) {
  var angle = Math.random() * Math.PI * 2
  return { vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed }
}

// Advances the physics state by dt seconds. `state` is a plain object with
// x, y, vx, vy, size, mode ("classic"|"gravity"), width, height (viewport).
// Mutates and returns it so callers can assign properties back in one pass.
function step(state, dt) {
  var s = state
  var gravity = 900
  var damping = 0.82

  if (s.mode === "gravity") s.vy += gravity * dt

  s.x += s.vx * dt
  s.y += s.vy * dt

  var maxX = Math.max(0, s.width - s.size)
  var maxY = Math.max(0, s.height - s.size)

  if (s.x < 0) { s.x = 0; s.vx = Math.abs(s.vx) }
  else if (s.x > maxX) { s.x = maxX; s.vx = -Math.abs(s.vx) }

  if (s.y < 0) {
    s.y = 0
    s.vy = Math.abs(s.vy)
  } else if (s.y > maxY) {
    s.y = maxY
    if (s.mode === "gravity") {
      s.vy = -Math.abs(s.vy) * damping
      if (Math.abs(s.vy) < 40) s.vy = 0
    } else {
      s.vy = -Math.abs(s.vy)
    }
  }

  return s
}
function hueColor(hueDeg) {
  var h = ((hueDeg % 360) + 360) % 360 / 60
  var i = Math.floor(h)
  var f = h - i
  var q = 1 - f
  var rgb
  switch (i) {
    case 0: rgb = [1, f, 0]; break
    case 1: rgb = [q, 1, 0]; break
    case 2: rgb = [0, 1, f]; break
    case 3: rgb = [0, q, 1]; break
    case 4: rgb = [f, 0, 1]; break
    default: rgb = [1, 0, q]; break
  }
  return "rgb(" + Math.round(rgb[0] * 255) + "," + Math.round(rgb[1] * 255) + "," + Math.round(rgb[2] * 255) + ")"
}

// Sphere-mapped checkerboard, drawn with plain vector clips (arcs + rects +
// pie slices) rather than per-pixel sampling. An earlier version of this
// reconstructed every pixel's 3D position with createImageData/putImageData
// for a mathematically exact projection -- it looked right, but repeatedly
// froze the whole Omarchy shell after 15-25s of continuous repainting (a
// resource leak somewhere in that pixel-buffer path, not just "slow"). This
// version is provably built from the same clip/arc/fill primitives already
// proven stable for hours of use elsewhere in this plugin.
//
// It isn't a pixel-exact sphere projection, but it captures the part that
// actually reads as spherical: latitude bands are spaced by `r*sin(lat)`
// rather than evenly, so they compress near the top/bottom silhouette the
// way a real sphere's surface foreshortens, instead of sitting in a flat,
// equal-height grid. Longitude wedges are pie slices from the center that
// rotate with `phase`, which is what keeps the checker pattern fixed to the
// ball's surface as it spins rather than sliding on top of it.
function drawAmigaChecker(ctx, r, phaseRad) {
  var latBands = 10
  var lonBands = 20
  var lonStep = Math.PI * 2 / lonBands

  var latBoundaries = []
  for (var i = 0; i <= latBands; i++) {
    var lat = -Math.PI / 2 + (i / latBands) * Math.PI
    latBoundaries.push(r * Math.sin(lat))
  }

  for (var bi = 0; bi < latBands; bi++) {
    var yTop = latBoundaries[bi]
    var bandHeight = latBoundaries[bi + 1] - yTop
    // Shading follows how face-on this band is (bands near the equator sit
    // flatter toward the viewer than the compressed ones near the poles),
    // echoing the diffuse falloff a real lit sphere would show.
    var midLat = -Math.PI / 2 + ((bi + 0.5) / latBands) * Math.PI
    var shade = 0.62 + 0.38 * Math.cos(midLat)

    for (var wj = 0; wj < lonBands; wj++) {
      ctx.save()
      ctx.beginPath()
      ctx.arc(0, 0, r, 0, Math.PI * 2)
      ctx.clip()
      ctx.beginPath()
      ctx.rect(-r, yTop, 2 * r, bandHeight)
      ctx.clip()
      ctx.beginPath()
      ctx.moveTo(0, 0)
      ctx.arc(0, 0, r * 1.5, phaseRad + wj * lonStep, phaseRad + (wj + 1) * lonStep)
      ctx.closePath()
      ctx.clip()
      var white = (bi + wj) % 2 === 0
      ctx.fillStyle = white
        ? "rgb(" + Math.round(245 * shade) + "," + Math.round(245 * shade) + "," + Math.round(245 * shade) + ")"
        : "rgb(" + Math.round(214 * shade) + "," + Math.round(41 * shade) + "," + Math.round(27 * shade) + ")"
      ctx.fillRect(-r, -r, 2 * r, 2 * r)
      ctx.restore()
    }
  }
}

// Draws the ball centered in a `size`x`size` canvas. `style` is
// "amiga" | "solid" | "rainbow"; `phaseDeg` is the current roll rotation used
// to spin the checker sphere (amiga) or just orient the highlight.
function drawBall(ctx, size, style, color, phaseDeg) {
  var r = size / 2
  ctx.clearRect(0, 0, size, size)

  if (style === "amiga") {
    ctx.save()
    ctx.translate(r, r)
    drawAmigaChecker(ctx, r, (phaseDeg || 0) * Math.PI / 180)
    ctx.restore()
  } else {
    ctx.save()
    ctx.translate(r, r)
    ctx.beginPath()
    ctx.arc(0, 0, r, 0, Math.PI * 2)
    ctx.fillStyle = style === "rainbow" ? hueColor(phaseDeg * 2) : color
    ctx.fill()
    ctx.restore()
  }

  ctx.save()
  ctx.translate(r, r)

  // Shared pseudo-3D shading: a soft dark rim and a glossy highlight so every
  // style reads as a sphere rather than a flat disc.
  var rim = ctx.createRadialGradient(0, 0, r * 0.6, 0, 0, r)
  rim.addColorStop(0, "rgba(0,0,0,0)")
  rim.addColorStop(1, "rgba(0,0,0,0.35)")
  ctx.beginPath()
  ctx.arc(0, 0, r, 0, Math.PI * 2)
  ctx.fillStyle = rim
  ctx.fill()

  var gloss = ctx.createRadialGradient(-r * 0.35, -r * 0.4, 0, -r * 0.35, -r * 0.4, r * 0.7)
  gloss.addColorStop(0, "rgba(255,255,255,0.55)")
  gloss.addColorStop(1, "rgba(255,255,255,0)")
  ctx.beginPath()
  ctx.arc(0, 0, r, 0, Math.PI * 2)
  ctx.fillStyle = gloss
  ctx.fill()

  ctx.restore()
}

if (typeof module !== "undefined") {
  module.exports = {
    sizePresets: sizePresets,
    speedPresets: speedPresets,
    stylePresets: stylePresets,
    physicsPresets: physicsPresets,
    colorSwatches: colorSwatches,
    clamp: clamp,
    randomVelocity: randomVelocity,
    hueColor: hueColor,
    drawBall: drawBall,
    step: step
  }
}
