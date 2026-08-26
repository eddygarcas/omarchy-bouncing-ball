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
  { label: "Image", value: "image" }
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

// Formats the Keep Awake slider's minute value: 0 is the "no timer, run
// until I stop it" end of the range, everything else reads as m/h.
function formatMinutes(minutes) {
  var n = Math.max(0, Math.round(Number(minutes) || 0))
  if (n <= 0) return "Until stopped"
  if (n < 60) return n + "m"
  var hours = n / 60
  return (hours % 1 === 0 ? hours.toFixed(0) : hours.toFixed(1)) + "h"
}

// Formats a millisecond countdown (e.g. keepAwakeEndsAt - Date.now()) for
// the live "stops in..." status line.
function formatRemainingMs(ms) {
  var totalMinutes = Math.ceil(Math.max(0, Number(ms) || 0) / 60000)
  if (totalMinutes <= 0) return "moments"
  if (totalMinutes < 60) return totalMinutes + "m"
  var hours = Math.floor(totalMinutes / 60)
  var mins = totalMinutes % 60
  return mins > 0 ? hours + "h " + mins + "m" : hours + "h"
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
// Precomputes the `latBands + 1` latitude boundary angles and their
// projected y-coordinates (`r*sin(lat)`), shared by every sphere-mapped
// style so they all foreshorten toward the poles identically.
function sphereLatBands(r, latBands) {
  var angles = []
  var boundaries = []
  for (var i = 0; i <= latBands; i++) {
    var lat = -Math.PI / 2 + (i / latBands) * Math.PI
    angles.push(lat)
    boundaries.push(r * Math.sin(lat))
  }
  return { angles: angles, boundaries: boundaries }
}

// Clips the canvas (already save()'d and translated to the ball's center) to
// one lat/lon cell's true curved boundary, built entirely from vector clips
// (arcs + rects + a sampled polygon) rather than per-pixel sampling. An
// earlier version of the checker style reconstructed every pixel's 3D
// position with createImageData/putImageData for a mathematically exact
// projection -- it looked right, but repeatedly froze the whole Omarchy
// shell after 15-25s of continuous repainting (a resource leak somewhere in
// that pixel-buffer path, not just "slow"). Every sphere-mapped style
// (checker, image) is built from this same clip plus a plain fillRect or
// drawImage, both cheap GPU-backed blits, never a raw pixel buffer.
//
// Under orthographic projection, a wedge's top/bottom edges are exactly
// horizontal regardless of longitude (fixed latitude -> fixed y), so those
// are plain straight lines via `rect`. But its left/right edges are
// meridians, and a meridian projects to an arc of an ellipse
// (x = amp*cos(phi), y = r*sin(phi), amp = r*sin(theta)), not a straight
// line to the ball's center -- sampling that curve is what keeps cells
// reading as wrapped around a sphere instead of flat pie slices.
function clipSphereCell(ctx, r, yTop, bandHeight, phiLo, phiHi, ampLeft, ampRight) {
  var samples = 4 // segments per left/right edge; plenty smooth at this band size
  ctx.beginPath()
  ctx.arc(0, 0, r, 0, Math.PI * 2)
  ctx.clip()
  ctx.beginPath()
  ctx.rect(-r, yTop, 2 * r, bandHeight)
  ctx.clip()
  ctx.beginPath()
  for (var s = 0; s <= samples; s++) {
    var phi = phiLo + (s / samples) * (phiHi - phiLo)
    var x = ampLeft * Math.cos(phi)
    var y = r * Math.sin(phi)
    if (s === 0) ctx.moveTo(x, y)
    else ctx.lineTo(x, y)
  }
  for (var t = samples; t >= 0; t--) {
    var phi2 = phiLo + (t / samples) * (phiHi - phiLo)
    ctx.lineTo(ampRight * Math.cos(phi2), r * Math.sin(phi2))
  }
  ctx.closePath()
  ctx.clip()
}

// Expands one cell's boundary angles slightly beyond its true span before
// it's handed to clipSphereCell. Two cells that share a mathematically exact
// boundary still leave a faint gap where the renderer's own edge
// anti-aliasing makes neither draw fully opaque right at the seam --
// visible as thin grid lines through the image style, and as a bit of extra
// "grout" on the checker style. A small overlap between neighbors papers
// over that rather than fighting the renderer's AA directly.
function bleedSphereCell(r, phiLo, phiHi, thetaLeft, thetaRight, lonStep) {
  var bleedPhi = (phiHi - phiLo) * 0.04
  var bleedTheta = lonStep * 0.04
  var bPhiLo = phiLo - bleedPhi
  var bPhiHi = phiHi + bleedPhi
  var yTop = r * Math.sin(bPhiLo)
  return {
    phiLo: bPhiLo,
    phiHi: bPhiHi,
    yTop: yTop,
    bandHeight: r * Math.sin(bPhiHi) - yTop,
    ampLeft: r * Math.sin(thetaLeft - bleedTheta),
    ampRight: r * Math.sin(thetaRight + bleedTheta)
  }
}

// `theta` sweeps the full 0-2pi longitude range every frame, which covers
// both the hemisphere facing the viewer and the one facing away -- an
// orthographic projection maps both to the exact same 2D disc, so without
// culling, every screen pixel would get painted twice, by two unrelated
// cells (front and back), and whichever the loop draws last would win. A
// point is front-facing (visible) exactly when cos(theta) > 0 -- z =
// r*cos(phi)*cos(theta), and cos(phi) is never negative -- so any cell whose
// entire theta span is back-facing is skipped, leaving only the actual
// visible hemisphere to paint. Both sphere-mapped styles share this test.
function sphereCellIsBackFacing(thetaLeft, thetaRight) {
  return Math.cos(thetaLeft) < 0 && Math.cos(thetaRight) < 0
}

function drawAmigaChecker(ctx, r, phaseRad) {
  var latBands = 10
  var lonBands = 20
  var lonStep = Math.PI * 2 / lonBands
  var bands = sphereLatBands(r, latBands)

  for (var bi = 0; bi < latBands; bi++) {
    var yTop = bands.boundaries[bi]
    var bandHeight = bands.boundaries[bi + 1] - yTop
    var phiLo = bands.angles[bi]
    var phiHi = bands.angles[bi + 1]
    // Shading follows how face-on this band is (bands near the equator sit
    // flatter toward the viewer than the compressed ones near the poles),
    // echoing the diffuse falloff a real lit sphere would show.
    var midLat = -Math.PI / 2 + ((bi + 0.5) / latBands) * Math.PI
    var shade = 0.62 + 0.38 * Math.cos(midLat)

    for (var wj = 0; wj < lonBands; wj++) {
      var thetaLeft = phaseRad + wj * lonStep
      var thetaRight = phaseRad + (wj + 1) * lonStep
      if (sphereCellIsBackFacing(thetaLeft, thetaRight)) continue

      var cell = bleedSphereCell(r, phiLo, phiHi, thetaLeft, thetaRight, lonStep)

      ctx.save()
      clipSphereCell(ctx, r, cell.yTop, cell.bandHeight, cell.phiLo, cell.phiHi, cell.ampLeft, cell.ampRight)
      var white = (bi + wj) % 2 === 0
      ctx.fillStyle = white
        ? "rgb(" + Math.round(245 * shade) + "," + Math.round(245 * shade) + "," + Math.round(245 * shade) + ")"
        : "rgb(" + Math.round(214 * shade) + "," + Math.round(41 * shade) + "," + Math.round(27 * shade) + ")"
      ctx.fillRect(-r, -r, 2 * r, 2 * r)
      ctx.restore()
    }
  }
}

// Wraps a user-picked image around the ball with a fisheye/orthographic
// mapping -- the image is treated as a flat circular photo glued to one
// hemisphere of the ball's surface, not as an equirectangular world map. An
// equirectangular wrap (linear-in-longitude) was the first approach here,
// but it slices an ordinary photo into ~20 disconnected vertical ribbons,
// because a normal photo's columns aren't meant to represent continuously
// adjacent longitudes the way an actual world map's are -- it read as
// sliced up rather than wrapped around a sphere.
//
// Both source axes here use `amp = r*sin(angle)` -- the same linear-disc
// spacing the destination geometry already uses for both the checker and
// this style -- instead of the angle itself, so the source image compresses
// toward the limb exactly the way the destination already does. That keeps
// one coherent, recognizable image across the visible hemisphere at any
// instant, rather than a filmstrip of narrow strips.
//
// Horizontal position uses each wedge's INTRINSIC longitude (`wj*lonStep`,
// not `phaseRad + wj*lonStep`) so a given patch of the image stays glued to
// the same patch of the ball's surface as it spins -- like a sticker on a
// rotating globe -- instead of the image scrolling sideways underneath the
// wedges as `phaseRad` advances.
//
// sin() only maps a 180-degree span onto the image monotonically, so a
// wedge is only textured if its intrinsic longitude falls within that one
// canonical front-facing span (`isImageDecalWedge`); the rest of the
// sphere -- the "back" of the sticker -- falls back to the plain `color`
// fill `solid` style already uses. Without that split, a rotation phase
// whose visible hemisphere straddles two different monotonic spans would
// sample the same source pixels from two different directions at once,
// which reads as the image folding back on itself right at the seam
// between those spans -- confirmed visually (rendered head-on with pycairo
// against a real photo, independent of any live-desktop screenshot) before
// settling on this fix over just documenting the fold as a known quirk.
function isImageDecalWedge(wj, lonStep) {
  return Math.cos((wj + 0.5) * lonStep) > 0
}

function drawImageSphere(ctx, r, phaseRad, image, imgWidth, imgHeight, color) {
  var latBands = 10
  var lonBands = 20
  var lonStep = Math.PI * 2 / lonBands
  var bands = sphereLatBands(r, latBands)

  for (var bi = 0; bi < latBands; bi++) {
    var yTop = bands.boundaries[bi]
    var bandHeight = bands.boundaries[bi + 1] - yTop
    var phiLo = bands.angles[bi]
    var phiHi = bands.angles[bi + 1]
    var sy = (yTop + r) / (2 * r) * imgHeight
    var sh = Math.max(0.5, bandHeight / (2 * r) * imgHeight)

    for (var wj = 0; wj < lonBands; wj++) {
      var thetaLeft = phaseRad + wj * lonStep
      var thetaRight = phaseRad + (wj + 1) * lonStep
      if (sphereCellIsBackFacing(thetaLeft, thetaRight)) continue

      // The destination rect is deliberately built from the same bled
      // (slightly overlapped) boundary as the clip, not the cell's true
      // span -- drawImage/fillRect only paint within their own dest rect
      // regardless of how big the clip is, so a bled clip with a tight
      // dest rect would still leave the seam.
      var cell = bleedSphereCell(r, phiLo, phiHi, thetaLeft, thetaRight, lonStep)
      var dx = Math.min(cell.ampLeft, cell.ampRight)
      var dw = Math.max(0.5, Math.abs(cell.ampRight - cell.ampLeft))

      ctx.save()
      clipSphereCell(ctx, r, cell.yTop, cell.bandHeight, cell.phiLo, cell.phiHi, cell.ampLeft, cell.ampRight)

      if (isImageDecalWedge(wj, lonStep)) {
        var ampTexLeft = r * Math.sin(wj * lonStep)
        var ampTexRight = r * Math.sin((wj + 1) * lonStep)
        var sx = (Math.min(ampTexLeft, ampTexRight) + r) / (2 * r) * imgWidth
        var sw = Math.max(0.5, Math.abs(ampTexRight - ampTexLeft) / (2 * r) * imgWidth)
        ctx.drawImage(image, sx, sy, sw, sh, dx, cell.yTop, dw, cell.bandHeight)
      } else {
        ctx.fillStyle = color
        ctx.fillRect(-r, -r, 2 * r, 2 * r)
      }

      ctx.restore()
    }
  }
}

// Draws the ball centered in a `size`x`size` canvas. `style` is
// "amiga" | "solid" | "image"; `phaseDeg` is the current roll rotation used
// to spin the checker/image sphere (amiga/image) or just orient the
// highlight. `image`/`imgWidth`/`imgHeight` are only needed for "image" --
// omit or pass a not-yet-loaded image and it falls back to a plain `color`
// fill, same as "solid".
function drawBall(ctx, size, style, color, phaseDeg, image, imgWidth, imgHeight) {
  var r = size / 2
  ctx.clearRect(0, 0, size, size)

  if (style === "amiga") {
    ctx.save()
    ctx.translate(r, r)
    drawAmigaChecker(ctx, r, (phaseDeg || 0) * Math.PI / 180)
    ctx.restore()
  } else if (style === "image" && image && imgWidth > 0 && imgHeight > 0) {
    ctx.save()
    ctx.translate(r, r)
    drawImageSphere(ctx, r, (phaseDeg || 0) * Math.PI / 180, image, imgWidth, imgHeight, color)
    ctx.restore()
  } else {
    ctx.save()
    ctx.translate(r, r)
    ctx.beginPath()
    ctx.arc(0, 0, r, 0, Math.PI * 2)
    ctx.fillStyle = color
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
    drawBall: drawBall,
    step: step,
    formatMinutes: formatMinutes,
    formatRemainingMs: formatRemainingMs
  }
}
