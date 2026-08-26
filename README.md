# Bouncing Ball

A customizable ball that bounces around your screen, [Amiga Boing
Ball](https://en.wikipedia.org/wiki/Amiga_Boing_Ball)-style, for
[Omarchy](https://omarchy.org/). Click the bar icon to start/stop it and
tweak its style, size, speed, and physics; click the ball itself to boop it
back into the air. It doubles as a "keep awake" tool: an optional mode
bounces the ball as a visible reminder while blocking your screen from
locking, sleeping, or dimming, for a duration you set with a slider.

## Install

```
omarchy plugin add https://github.com/eddygarcas/omarchy-bouncing-ball.git --enable
```

Or manually:

```
git clone https://github.com/eddygarcas/omarchy-bouncing-ball.git \
  ~/.config/omarchy/plugins/eduard.bouncing-ball
omarchy-shell shell rescanPlugins
omarchy plugin enable eduard.bouncing-ball
```

## Remove

```
omarchy plugin remove eduard.bouncing-ball
```

This deletes `~/.config/omarchy/plugins/eduard.bouncing-ball/` and removes
the widget from your bar layout. There's nothing else to clean up: settings
are in-memory only (see below), and the plugin writes no files and starts no
external processes.

## What it does

Click the bar icon (a plain circle) to open the panel:

- **Bounce!** — starts/stops the ball.
- **Style** — Amiga (red/white checker sphere), Solid (pick from 6 colors),
  or Image (wrap a picture of your own around it — click **Choose Image…**
  to pick one from `~/Pictures` via Omarchy's own image picker).
- **Size** — S / M / L / XL.
- **Speed** — Chill / Normal / Fast / Turbo.
- **Physics** — Classic bounce (constant velocity, bounces off all four
  edges forever, DVD-logo style) or Gravity drop (falls, loses energy each
  bounce, eventually settles and rolls along the floor).
- **Keep Awake** — a toggle plus a slider (0 to 3 hours, in 5-minute steps;
  0 means "until you turn it off"). Turning it on starts the ball bouncing
  if it isn't already and inhibits the system idle cycle for the chosen
  duration, so the screensaver, lock, and auto-suspend won't fire — handy
  for watching a long build finish or a video call without input. It stops
  itself automatically when the timer runs out, or turn it off (or hit
  **Bounce!**) to end it early. Dragging the slider while it's already on
  re-arms the countdown immediately with the new duration.

Click the ball itself at any point to boop it — it kicks upward and nudges
sideways *away* from wherever you clicked, like batting a real ball. That
works whether it's mid-bounce or has already settled at the bottom in
Gravity mode, so repeated clicking is how you keep it going.

It renders as a full-screen, click-through overlay (the same technique
Omarchy's own on-screen-display uses): everywhere except the ball itself
stays click-through, so it never blocks the desktop underneath it. A
background service owns the physics so it keeps running independently of
whether the settings panel is open.

Keep Awake works through the standard Wayland `idle-inhibit-v1` protocol
(Quickshell's `IdleInhibitor`, attached to the overlay window) rather than
touching Omarchy's own idle/lock settings or its separate built-in "Stay
Awake" indicator — Omarchy's idle service already runs its idle detection
with `respectInhibitors: true`, so this is the same mechanism any other
idle-inhibiting app (a video player, a video call client) would use, and it
stays fully self-contained: nothing outside this plugin's own state changes,
and nothing persists once it's off.

## Known limitations

- **Single monitor.** It bounces on whichever screen its overlay window
  lands on; there's no per-monitor roaming.
- **Settings don't persist** across `omarchy restart shell` — resets to
  Amiga / Medium / Normal / Classic bounce each time. In-memory only, no
  config file, since this is a toy rather than something worth persisting.
- **Neither the Amiga checker nor the Image style is a pixel-exact sphere
  projection**, but both are close. Both are tessellated into the same grid
  of lat/lon cells: latitude bands are spaced by `r*sin(latitude)` so they
  genuinely compress near the top/bottom like a real sphere's
  foreshortening, and each cell's left/right edges are sampled along the
  actual projected meridian ellipse (`x = r*sin(theta)*cos(phi)`, `y =
  r*sin(phi)`) instead of straight radii to the center, so both read as
  wrapped around a sphere rather than flat pie slices. Cells whose entire
  longitude span faces away from the viewer (`cos(theta) < 0`) are culled
  before drawing -- without that, front and back cells land on the exact
  same screen pixels under orthographic projection, and painter's-order
  overdraw made the two halves of the ball appear to spin in opposite
  directions as `phase` advanced. Two more approximations: each meridian
  edge is a handful of line segments rather than a true curve (invisible at
  the current band count, would show as faceting if `latBands` were lowered
  a lot), and adjacent cells are deliberately given a small (~4%) overlap
  ("bleed") rather than sharing an exact boundary -- two independently
  clipped draws that share a mathematically exact edge still leave a faint
  anti-aliased seam where neither is fully opaque, which reads as thin grid
  lines through an Image texture and extra "grout" on the checker.
- **Do not reintroduce per-pixel canvas rendering for the Amiga/Image
  textures.** An earlier version used `createImageData`/`putImageData` to
  reconstruct each pixel's 3D position for a mathematically exact sphere
  projection. It looked right, but reliably froze the entire Omarchy shell
  after roughly 15-25 seconds of continuous repainting -- confirmed via
  CPU-monitored soak tests, independent of texture resolution, throttling,
  or the input-region mask. The current implementation avoids that path
  entirely: both styles draw only with vector primitives and single
  GPU-backed blits (`arc`/`clip`/`fillRect`/`moveTo`/`lineTo`/`drawImage`,
  never a raw pixel buffer read/write), soak-tested clean with flat CPU and
  no RSS growth over a minute of continuous Image-style repainting. If you
  improve the sphere accuracy, keep it on that side of the line.
- **The Image style uses a fisheye/orthographic mapping, not an
  equirectangular one.** An equirectangular wrap (the same flat layout as a
  world map) was the first approach, but it assumes the source image
  already reads as that kind of map -- an ordinary photo doesn't, so it got
  sliced into ~20 disconnected vertical ribbons instead of reading as
  wrapped around a sphere. The current approach instead treats the image as
  a flat circular photo glued to the ball's surface: both source axes use
  `amp = r*sin(angle)` (the same linear-disc spacing the destination
  geometry and the checker style already use) rather than the angle itself,
  so the image compresses toward the limb the way the sphere's own
  foreshortening already does, and a given patch of the image stays glued
  to the same patch of the ball's surface as it spins (using each cell's
  *intrinsic* longitude, not the rotated one) instead of scrolling
  sideways underneath the wedges. The image covers the whole ball, not
  just one hemisphere: `sin` isn't globally monotonic over a full turn
  (it rises across the front quarter-turns and mirrors back down across
  the back ones), so the back hemisphere shows the image mirrored rather
  than a second, independent copy -- the two meet exactly at the image's
  own left/right edges, with no jump. An earlier version limited the
  image to only the front hemisphere (falling back to a plain `color`
  fill on the back) specifically to dodge that mirroring; dropped after
  a synthetic striped test image and a standalone pycairo render
  (independent of any live-desktop screenshot) showed the "fold" that
  motivated the split was actually this same clean, expected mirror --
  it only read as broken on a *photo of a sphere itself* (its own margins
  and radial shading, not the mapping, were the actual source of the
  mess), and the fallback wasn't worth losing full coverage over.
- **The Image style's cells have straight left/right edges, not the true
  curved meridian edges the Amiga checker's cells have.** QtQuick's Canvas
  silently drops a `drawImage` call once the active clip is the full
  circle+rect+meridian-polygon stack `clipSphereCell` builds -- confirmed
  empirically by process of elimination: the identical clip stack with
  `fillRect` (what the checker style uses) never drops a paint; forcing
  a larger destination rect didn't help at any size tried, ruling out "the
  destination is too thin"; a `createPattern`+`fillRect` swap-in for
  `drawImage` rendered nothing at all (pattern fills aren't supported
  here); and progressively simplifying the clip -- circle alone, then
  circle+rect -- made the missing cells reappear right as the meridian
  polygon was dropped, and stayed gone once it was. So the Image style
  clips to a plain rect (circle + the cell's own bounding box) instead:
  still correctly positioned, sized, and foreshortened, just with a flat
  edge where the polygon version would have a slight curve -- invisible at
  the current cell count in practice, and a much better trade than the
  gaps a bugged `drawImage` call left in their place.

## Permissions & dependencies

- No external packages or network access required.
- Runs entirely inside the shared `omarchy-shell` process via a background
  service, a bar-widget settings panel, and a full-screen click-through
  overlay -- no separate processes, no files written to disk.
- **Choose Image…** shells out to `omarchy-menu-images` (ships with
  Omarchy) pointed at `~/Pictures`, the same fullscreen picker used for
  wallpapers and themes, rather than this plugin reimplementing a file
  browser. It's a real subprocess (`Quickshell.Io.Process`), so it can't
  block the shell; only the picked file's path comes back, read from its
  own stdout.
- Keep Awake uses the standard Wayland `idle-inhibit-v1` protocol (via
  Quickshell's `IdleInhibitor`) to block screensaver/lock/suspend while it's
  on -- the same mechanism any idle-inhibiting app uses, not a custom
  workaround. It only takes effect while this plugin's overlay window is
  visible and Keep Awake is toggled on, and stops the moment either is off.
- Like every Quickshell plugin, this code runs unsandboxed inside that
  shared process -- review `Panel.qml` / `Service.qml` / `Overlay.qml` /
  `Model.js` before installing.

## Files

| File           | Purpose                                                        |
|----------------|-----------------------------------------------------------------|
| `manifest.json`| Plugin manifest (`service` + `bar-widget` + `overlay`)          |
| `Panel.qml`    | Bar icon + settings panel                                       |
| `Service.qml`  | Background physics + Keep Awake + image-picker state, IPC        |
| `Overlay.qml`  | Full-screen click-through window that renders the ball          |
| `Model.js`     | Presets, physics step function, and the ball-drawing routines   |

## License

MIT — see [LICENSE](LICENSE).
