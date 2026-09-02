import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  // Injected by omarchy-shell: the sibling Service.qml instance for this
  // plugin id, handed over automatically because this kind pairs with a
  // "service" kind in the same manifest.
  property var service: null

  PanelWindow {
    id: window
    visible: !!(root.service && root.service.enabled)
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "eduard-bouncing-ball"
    WlrLayershell.layer: WlrLayer.Overlay
    // Only "landing" mode ever wants keyboard input (Up/Left/Right thrust
    // -- see keyCapture below), and even then only once the player has
    // actually clicked the ball to engage it -- see `wantsFocus` and
    // `focusReleaseCatcher` below. Landing mode landed here through two
    // rounds of live testing that both turned out wrong:
    //
    // Round 1 (Exclusive the whole time Landing was selected+bouncing):
    // confirmed live to hijack the ENTIRE session's keyboard AND mouse for
    // the whole duration, not just while a thrust key was held.
    //
    // Round 2 (OnDemand the whole time, primed via a brief Exclusive burst
    // on becoming active -- the same pattern Omarchy's own
    // KeyboardPanel.qml uses): still confirmed live, with real synthetic
    // clicks via `ydotool` and `hyprctl activewindow` as ground truth (not
    // just visual impression), to swallow clicks aimed at OTHER windows
    // entirely -- `hyprctl activewindow` never changed even when clicking
    // squarely inside another window's geometry. Root cause: this overlay
    // stays mapped/visible continuously for the whole bouncing session
    // (`visible` depends only on `enabled`, not `mode`), and in this
    // Hyprland version, once a layer-shell surface holds ANY non-None
    // keyboard-interactivity (Exclusive OR OnDemand), it appears to
    // capture pointer input for its full extent, not just its declared
    // `mask` input region -- contradicting the plain wlr-layer-shell spec,
    // but empirically reproducible.
    //
    // Because of that, the only surface-side way to actually let clicks
    // reach other windows while holding keyboard focus is what
    // KeyboardPanel.qml also does: catch every click yourself, full-screen,
    // and immediately drop keyboard focus (and shrink the input region back
    // down) the instant a click lands somewhere other than the thing that's
    // supposed to keep focus. `wantsFocus` is that state -- true only
    // between an explicit click on the ball (see canvas's MouseArea below)
    // and the next click anywhere else (see `focusReleaseCatcher`).
    readonly property bool landingActive: !!(root.service && root.service.enabled && root.service.mode === "landing")
    property bool wantsFocus: false
    property bool focusPrimed: false
    WlrLayershell.keyboardFocus: wantsFocus
      ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None

    // Safety net: leaving Landing mode (switching physics, picking a
    // different style, or stopping the ball) always drops focus immediately,
    // even if the player never explicitly clicked away first.
    onLandingActiveChanged: if (!landingActive) wantsFocus = false

    onWantsFocusChanged: {
      if (wantsFocus) {
        focusPrimed = false
        focusPrimeTimer.restart()
      } else {
        focusPrimeTimer.stop()
        focusPrimed = false
      }
    }

    Timer {
      id: focusPrimeTimer
      interval: 75
      onTriggered: if (window.wantsFocus) window.focusPrimed = true
    }
    exclusionMode: ExclusionMode.Ignore
    // Normally the clickable input region tracks only the ball's bounding
    // box via `hitboxAnchor`, so the rest of the screen stays click-through
    // -- see `maskSyncTimer` below. While `wantsFocus` is true, though, the
    // mask widens to the full window so `focusReleaseCatcher` can actually
    // see the click that should release focus (see the block comment on
    // `keyboardFocus` above for why this widen-then-release dance is
    // necessary at all here).
    mask: Region {
      x: window.wantsFocus ? 0 : hitboxAnchor.x
      y: window.wantsFocus ? 0 : hitboxAnchor.y
      width: window.wantsFocus ? window.width : hitboxAnchor.width
      height: window.wantsFocus ? window.height : hitboxAnchor.height
    }

    // Backs the "Keep Awake" panel toggle: this is the standard Wayland
    // idle-inhibit-v1 protocol, which the built-in idle/lock service already
    // respects (its IdleMonitor runs with respectInhibitors: true) -- so
    // enabling this is enough to block screensaver/lock/suspend system-wide,
    // with no need to reach into that other service's own state.
    IdleInhibitor {
      window: window
      enabled: !!(root.service && root.service.keepAwake && root.service.enabled)
    }

    onWidthChanged: if (root.service) root.service.viewportWidth = width
    onHeightChanged: if (root.service) root.service.viewportHeight = height
    // "orbit" mode only: hyprctl reports the cursor in Hyprland's GLOBAL
    // (all-monitors) coordinate space, but everything else here (x, y,
    // attractorX/Y) is local to this window's own output -- see the
    // screenOffsetX/Y comment in Service.qml. `screen` isn't necessarily
    // assigned yet at Component.onCompleted (confirmed live: it read back
    // as still unset there), so this also re-syncs on `screenChanged` --
    // whichever fires first with a real value wins; the window's own
    // output doesn't change at runtime in practice, so no ongoing binding
    // is needed beyond that.
    onScreenChanged: syncScreenOffset()
    Component.onCompleted: {
      if (!root.service) return
      root.service.viewportWidth = width
      root.service.viewportHeight = height
      syncScreenOffset()
    }
    function syncScreenOffset() {
      if (!root.service || !window.screen) return
      root.service.screenOffsetX = window.screen.x
      root.service.screenOffsetY = window.screen.y
    }

    // Stand-in the input-region mask tracks instead of the fast-moving
    // canvas -- see the comment on `mask` above. Position is copied over
    // imperatively by maskSyncTimer, not bound reactively, which is the
    // part that actually decouples it from the 60Hz physics loop.
    Item {
      id: hitboxAnchor
      width: root.service ? root.service.size : 0
      height: root.service ? root.service.size : 0
    }

    // Catches the click that should give focus back to whatever's below --
    // only present at all while `wantsFocus` is true (i.e. only while the
    // mask above has been widened to full-screen; see the block comment on
    // `keyboardFocus`). Declared before `canvas` so canvas -- rendered and
    // hit-tested after it -- wins for clicks actually on the ball; this
    // only ever sees clicks that land outside canvas's own bounds. Dropping
    // `wantsFocus` here doesn't forward this specific click through to the
    // window underneath (Wayland has no such "forward" operation from a
    // client), so the ball itself grabs the mouse for exactly one click to
    // release; the very next click reaches the real target normally, once
    // the mask has shrunk back down to just the ball's hitbox again.
    MouseArea {
      id: focusReleaseCatcher
      anchors.fill: parent
      enabled: window.wantsFocus
      acceptedButtons: Qt.AllButtons
      onPressed: window.wantsFocus = false
    }

    // Reads Up/Left/Right thrust into the service while "landing" mode has
    // keyboard focus (see WlrLayershell.keyboardFocus above) -- tracked as
    // plain held/released state (not relying on OS key-repeat) so thrust is
    // smooth and continuous for as long as a key is actually down. Release
    // events aren't autorepeated by Qt, only press events are, so onReleased
    // firing at all is always a genuine key-up; onPressed doesn't need to
    // distinguish a repeat from the original press since setting an
    // already-true flag back to true is a no-op.
    Item {
      id: keyCapture
      anchors.fill: parent
      focus: window.wantsFocus
      Keys.onPressed: function(event) {
        if (!root.service) return
        if (event.key === Qt.Key_Up) { root.service.thrustUp = true; event.accepted = true }
        else if (event.key === Qt.Key_Left) { root.service.thrustLeft = true; event.accepted = true }
        else if (event.key === Qt.Key_Right) { root.service.thrustRight = true; event.accepted = true }
      }
      Keys.onReleased: function(event) {
        if (!root.service) return
        if (event.key === Qt.Key_Up) { root.service.thrustUp = false; event.accepted = true }
        else if (event.key === Qt.Key_Left) { root.service.thrustLeft = false; event.accepted = true }
        else if (event.key === Qt.Key_Right) { root.service.thrustRight = false; event.accepted = true }
      }
    }

    Timer {
      id: maskSyncTimer
      interval: 66
      running: !!(root.service && root.service.enabled)
      repeat: true
      triggeredOnStart: true
      onTriggered: {
        hitboxAnchor.x = canvas.x
        hitboxAnchor.y = canvas.y
      }
    }

    // Backs the "image" style: the source texture wrapped around the ball
    // in Model.drawImageSphere. Loaded via the QML Image element (not
    // Canvas.loadImage(url)) so its natural pixel size is available as
    // sourceSize -- the equirectangular source-rect math needs real pixels,
    // not the destination canvas size.
    Image {
      id: textureImage
      visible: false
      asynchronous: true
      cache: true
      source: root.service && root.service.style === "image" && root.service.imagePath
        ? Util.fileUrl(root.service.imagePath)
        : ""
      onStatusChanged: {
        if (status === Image.Ready) {
          colorSampleCanvas.avgColor = ""
          colorSampleCanvas.requestPaint()
        }
        canvas.requestPaint()
      }
    }

    // Samples the just-loaded image's BACKGROUND color ONCE per image pick,
    // for drawImageSphere's un-decaled-hemisphere fallback fill (see its
    // docblock in Model.js) -- not a per-frame per-pixel reconstruction of
    // the sphere, which is the thing this plugin's history says never to
    // reintroduce (see Model.js's note on the old createImageData/
    // putImageData approach freezing the whole shell). A single getImageData
    // read of a tiny downscaled canvas, done once when an image is picked,
    // is a fundamentally different cost than that.
    //
    // Averages only the outermost ring of pixels, not the whole image: a
    // typical picked photo is a subject (here, a ball) roughly centered
    // against a plain backdrop, so the backdrop is what reaches the edges
    // while the subject usually doesn't. Averaging every pixel instead
    // pulled the result toward whatever color the subject itself was
    // (e.g. a red/white checker ball averaging to a muted pink) rather than
    // the actual background behind it (plain white, for that same photo).
    // 32x32, not smaller: at 16x16 each border pixel is a bilinear blend of
    // a 16x16 block of source pixels, which was close enough to the ball's
    // silhouette in a test photo to still smudge red into the "background"
    // read -- 32x32 halves that per-pixel source footprint and landed on
    // the actual background color cleanly. Still a one-shot cost, not a
    // per-frame one.
    Canvas {
      id: colorSampleCanvas
      visible: false
      width: 32
      height: 32
      property string avgColor: ""

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.drawImage(textureImage, 0, 0, width, height)
        var data
        try {
          data = ctx.getImageData(0, 0, width, height).data
        } catch (e) {
          return
        }
        var r = 0, g = 0, b = 0, alphaSum = 0, pixelCount = 0
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            if (x !== 0 && x !== width - 1 && y !== 0 && y !== height - 1) continue
            var i = (y * width + x) * 4
            var a = data[i + 3]
            r += data[i] * a
            g += data[i + 1] * a
            b += data[i + 2] * a
            alphaSum += a
            pixelCount++
          }
        }
        // QtQuick's Canvas has a history of silently dropping drawImage
        // calls (see Model.js) -- a near-zero alpha sum means this paint
        // was one of them, not that the image is mostly transparent, so
        // leave avgColor unset rather than reporting black as the average.
        if (alphaSum < pixelCount * 8) return
        avgColor = "rgb(" + Math.round(r / alphaSum) + "," + Math.round(g / alphaSum) + "," + Math.round(b / alphaSum) + ")"
      }

      onAvgColorChanged: canvas.requestPaint()
    }

    // "blackhole" style only: the real desktop wallpaper, loaded once and
    // reused as the lensing halo's texture source below (the DEFAULT
    // source -- see blackholeLiveCapture below for the opt-in alternative).
    // Hidden -- like textureImage above, it exists purely to hand pixels to
    // a ShaderEffectSource, never drawn directly. This window sits at
    // WlrLayer.Overlay, ABOVE every app window, so a plain full-opacity
    // copy of the wallpaper drawn here would blank out the whole desktop,
    // not just stand in for the real wallpaper layer underneath. Same
    // PreserveAspectCrop fill mode + full-window size as Omarchy's own
    // /usr/share/omarchy/shell/plugins/background/Background.qml, so this
    // copy crops identically to the real thing and a locally-warped patch
    // of it lines up seamlessly with the real wallpaper just outside it.
    Image {
      id: wallpaperImage
      visible: false
      anchors.fill: parent
      asynchronous: true
      cache: true
      fillMode: Image.PreserveAspectCrop
      source: root.service && root.service.style === "blackhole" && !root.service.blackholeLiveCapture && root.service.wallpaperPath
        ? Util.fileUrl(root.service.wallpaperPath)
        : ""
    }

    // Opt-in alternative to wallpaperImage above (see Service.qml's
    // blackholeLiveCapture doc comment for the cost/privacy reasoning): a
    // ONE-SHOT snapshot of this monitor's real composited output, via
    // Quickshell's ScreencopyView (Hyprland's wlr-screencopy protocol --
    // the same one `grim` uses), then held and reused exactly like
    // wallpaperImage's static file -- NOT a continuous live feed. Confirmed
    // directly against Quickshell's own C++ source (view.cpp): with `live:
    // false`, setting `captureSource` triggers exactly one automatic
    // capture (`captureFrame()` called once from `createContext()`), and
    // `hasContent` then stays true holding that single frame -- no
    // per-frame re-capture happens the way `live: true` does. This is
    // deliberately closer to "take a screenshot, then treat it like a
    // background image" than to real-time screen mirroring: much cheaper
    // than continuous capture, and the halo's actual warp math is
    // downstream and identical either way (see haloSource/haloEffect
    // below), so this reuses the exact same rendering path wallpaperImage
    // already does -- the only difference is where the one static texture
    // came from. `captureSource` is set to null whenever this isn't the
    // active mode (confirmed via the same source: nulling it destroys the
    // context and discards the held frame, `hasContent` goes back to
    // false) rather than just left bound-but-unused, so this never holds
    // captured screen content in memory outside of Black Hole + Live
    // Screen Capture actually being active+bouncing. Re-entering that
    // state (e.g. re-toggling, or restarting the ball) takes a fresh
    // snapshot each time, same as re-picking the same file would reload
    // wallpaperImage.
    ScreencopyView {
      id: screenCapture
      visible: false
      anchors.fill: parent
      live: false
      captureSource: (root.service && root.service.enabled && root.service.style === "blackhole"
        && root.service.blackholeLiveCapture && window.screen) ? window.screen : null
    }

    // Crops whichever of the two sources above is active down to a small
    // square centered on the ball -- see lens.frag's own docblock for why
    // the shader itself only ever needs to deal with plain 0..1 local UV
    // once this crop is done here. `visible: false` so this item itself
    // never draws the UNdistorted patch directly; only haloEffect below
    // (which samples this as a texture) is ever actually shown.
    ShaderEffectSource {
      id: haloSource
      visible: false
      sourceItem: (root.service && root.service.blackholeLiveCapture) ? screenCapture : wallpaperImage
      live: true
      width: root.service ? root.service.size * 4 : 0
      height: width
      sourceRect: Qt.rect(
        (root.service ? root.service.x + root.service.size / 2 : 0) - width / 2,
        (root.service ? root.service.y + root.service.size / 2 : 0) - height / 2,
        width, height
      )
    }

    // Declared BEFORE `canvas` below so the ball itself, painted after,
    // naturally covers this layer's own center -- the "event horizon" is
    // just the opaque ball on top, nothing here needs to know its shape.
    // `horizon` (0.25) is a fixed constant, not computed per-frame: it's
    // the ball's radius as a fraction of this halo's own half-width, i.e.
    // (size/2) / (size*4/2), which cancels `size` out entirely. `strength`
    // scales with the existing Gravity slider/presets (see Panel.qml) so
    // "stronger gravity" reads as "stronger visual pull" too, same knob
    // Zero-G Orbit's actual motion already uses.
    ShaderEffect {
      id: haloEffect
      visible: !!(root.service && root.service.enabled && root.service.style === "blackhole"
        && (root.service.blackholeLiveCapture ? screenCapture.hasContent : wallpaperImage.status === Image.Ready))
      width: haloSource.width
      height: haloSource.height
      x: haloSource.sourceRect.x
      y: haloSource.sourceRect.y

      property variant source: haloSource
      property real strength: root.service ? 0.05 * (root.service.gravity / 900) : 0.05
      property real swirl: 0.6
      property real horizon: 0.25

      fragmentShader: "lens.frag.qsb"
    }

    Canvas {
      id: canvas
      visible: !!(root.service && root.service.enabled)
      width: root.service ? root.service.size : 0
      height: root.service ? root.service.size : 0
      x: root.service ? root.service.x : 0
      y: root.service ? root.service.y : 0

      onPaint: {
        if (!root.service) return
        var ctx = getContext("2d")
        var useImage = root.service.style === "image" && textureImage.status === Image.Ready
        Model.drawBall(
          ctx, root.service.size, root.service.style, root.service.color, root.service.rotation,
          useImage ? textureImage : null,
          useImage ? textureImage.sourceSize.width : 0,
          useImage ? textureImage.sourceSize.height : 0,
          colorSampleCanvas.avgColor
        )
      }

      // Position (x/y) updates every physics tick via plain item bindings
      // above, which the scene graph handles as a cheap transform -- no
      // repaint needed for motion alone. Repainting the canvas *contents*
      // (the spin, in particular) only needs to happen often enough to look
      // smooth, not on every single 60Hz physics tick, so it's throttled
      // here to a fixed ~24fps independent of the physics rate.
      Timer {
        interval: 42
        running: !!(root.service && root.service.enabled)
        repeat: true
        onTriggered: canvas.requestPaint()
      }

      Connections {
        target: root.service
        function onStyleChanged() { canvas.requestPaint() }
        function onColorChanged() { canvas.requestPaint() }
        function onSizeChanged() { canvas.requestPaint() }
        function onImagePathChanged() { canvas.requestPaint() }
      }

      // Click the ball to boop it back into the air -- offset from center
      // is passed through so a swat to one side sends it the other way.
      // Distance-check against the radius so the mask's square corners
      // (outside the visually round ball) don't count as a hit. In Landing
      // mode this same click is also what engages `wantsFocus` (see the
      // block comment on `keyboardFocus` above) -- clicking the ball both
      // boops it and hands it keyboard control in one gesture.
      MouseArea {
        anchors.fill: parent
        onClicked: function(mouse) {
          if (!root.service) return
          var r = canvas.width / 2
          var dx = mouse.x - r
          var dy = mouse.y - r
          if (dx * dx + dy * dy > r * r) return
          root.service.hit(dx, dy)
          if (root.service.mode === "landing") window.wantsFocus = true
        }
      }
    }
  }
}
