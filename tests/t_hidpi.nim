## Tests for HiDPI / fractional UI scaling support.
##
## A UiWindow with `uiScale = s` lays out all components in logical pixels
## (window size = framebuffer size / s), while rendering happens at device
## pixel resolution, so text and geometry stay sharp on HiDPI displays.
##
## Run: nim r t_hidpi.nim

import unittest
import pkg/[chroma, vmath]
import pkg/pixie
import sigui, sigui/testutils
import sigui/rendering/any

const typefaceData = staticRead "Roboto-Regular.ttf"


var win: HeadlessUiWindow

proc makeWin(scale: float32) =
  ## framebuffer is always 200x100 device pixels
  win = newHeadlessUiWindow(size = ivec2(200, 100))
  win.clearColor = color(1, 1, 1, 1)
  win.uiScale[] = scale
  win.setupOffscreenFramebuffer(ivec2(200, 100))


proc devicePixel(pos: Vec2): Color = win.windowPixelColor(pos)


suite "hidpi scaling":

  test "window size is reported in logical pixels":
    makeWin(2)
    check win.wh == vec2(100, 50)
    check win.uiScale[] == 2

    makeWin(1.5)
    check win.wh == vec2(200 / 1.5, 100 / 1.5)

  test "scale 1 renders as before":
    makeWin(1)
    win.makeLayout:
      - UiRect.new:
        x = 10
        y = 10
        w = 20
        h = 20
        color = color(1, 0, 0, 1)
    win.render()
    check devicePixel(vec2(20, 20)) == color(1, 0, 0, 1)
    check devicePixel(vec2(5, 20)) == color(1, 1, 1, 1)
    check devicePixel(vec2(35, 20)) == color(1, 1, 1, 1)
    check devicePixel(vec2(20, 5)) == color(1, 1, 1, 1)
    check devicePixel(vec2(20, 35)) == color(1, 1, 1, 1)

  test "rects are placed at logical coordinates, rendered at device resolution":
    makeWin(2)
    win.makeLayout:
      - UiRect.new:
        x = 10
        y = 10
        w = 20
        h = 20
        color = color(1, 0, 0, 1)
    win.render()
    # logical (10..30) * 2 = device (20..60)
    check devicePixel(vec2(40, 40)) == color(1, 0, 0, 1)
    check devicePixel(vec2(15, 40)) == color(1, 1, 1, 1)
    check devicePixel(vec2(65, 40)) == color(1, 1, 1, 1)
    check devicePixel(vec2(40, 15)) == color(1, 1, 1, 1)
    check devicePixel(vec2(40, 65)) == color(1, 1, 1, 1)

  test "fill works in logical pixels":
    makeWin(2)
    win.makeLayout:
      - UiRect.new:
        this.fill(parent, 10)  # 10 logical px margins
        color = color(1, 0, 0, 1)
    win.render()
    # logical (10..90, 10..40) -> device (20..180, 20..80)
    check devicePixel(vec2(100, 50)) == color(1, 0, 0, 1)
    check devicePixel(vec2(45, 10)) == color(1, 1, 1, 1)  # logical y=5 < 10
    check devicePixel(vec2(45, 90)) == color(1, 1, 1, 1)  # logical y=45 > 40
    check devicePixel(vec2(45, 45)) == color(1, 0, 0, 1)

  test "clip rect clips at logical bounds":
    makeWin(2)
    win.makeLayout:
      - ClipRect.new:
        x = 0
        y = 0
        w = 50
        h = 25
        - UiRect.new:
          x = 40
          y = 20
          w = 30
          h = 30
          color = color(1, 0, 0, 1)
    win.render()
    # the child rect extends to logical (70, 50) but is clipped at (50, 25)
    check devicePixel(vec2(90, 45)) == color(1, 0, 0, 1)   # inside clip and rect
    check devicePixel(vec2(120, 45)) == color(1, 1, 1, 1)  # device x=60 > clip 50
    check devicePixel(vec2(90, 60)) == color(1, 1, 1, 1)   # device y=30 > clip 25

  test "text is rendered at device resolution":
    makeWin(2)
    let fnt = any.parseTtf(typefaceData).withSize(20)
    win.makeLayout:
      - UiText.new:
        x = 10
        y = 10
        this.font[] = fnt
        text = "Ha"
        color = color(0, 0, 0, 1)
    win.render()

    # count dark pixels in the text area: with sharp rendering at scale 2
    # there must be plenty of them
    var dark = 0
    for y in 20 ..< 70:
      for x in 20 ..< 90:
        if devicePixel(vec2(x.float32, y.float32)).r < 0.5:
          inc dark
    check dark > 30

  test "svg images are rendered at device resolution":
    makeWin(2)
    var icon: UiSvgImage
    win.makeLayout:
      - UiSvgImage.new as (icon):
        x = 10
        y = 10
        this.image[] = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 10 10\"><rect x=\"0\" y=\"0\" width=\"10\" height=\"10\" fill=\"white\"/></svg>"
    win.render()
    check icon.wh == vec2(10, 10)          # logical size is preserved
    check icon.imageWh[] == ivec2(20, 20)  # texture is at device resolution
    check devicePixel(vec2(25, 25)) == color(0, 0, 0, 1)
    check devicePixel(vec2(15, 25)) == color(1, 1, 1, 1)
    check devicePixel(vec2(45, 25)) == color(1, 1, 1, 1)

  test "mouse state is converted to logical pixels":
    makeWin(2)
    # siwin updates window.mouse before dispatching the event, positions are device pixels
    win.siwinWindow.mouse.pos = vec2(30, 40)
    win.siwinWindow.eventsHandler.onMouseMove(
      MouseMoveEvent(window: win.siwinWindow, pos: vec2(30, 40), kind: MouseMoveKind.move)
    )
    check win.mouseState.pos == vec2(15, 20)

  test "emulated input works in logical pixels":
    makeWin(2)
    var area: MouseArea
    win.makeLayout:
      - MouseArea.new as (area):
        this.fill(parent)
    win.render()
    win.hoverAt(vec2(80, 30))  # logical
    check area.hovered[]
    check area.mouseXy[] == vec2(80, 30)
