## Demonstration of sigui/inspector usage
##
## Opens the application window together with an inspector window.
## Try the crosshair button in the inspector (or set `picking = true`)
## and click any element of the demo window to inspect it.
##
## Run: nim r inspector.nim

import pkg/[chroma, vmath]
import sigui, sigui/inspector

let win = newUiWindow(size = ivec2(640, 480), title = "Inspector demo")
let typeface = findSystemFont()

var clicks = 0.property

win.makeLayout:
  this.clearColor = "#ffffff".color

  - Layout.new:
    this.fill(parent, 24)
    orientation = vertical
    gap = 12

    - UiText.new:
      text = "Demo application"
      font = typeface.withSize(22)

    - UiRect.new as red:
      w = 180
      h = 60
      radius = 8
      color = binding:
        if mouseR.pressed[]: "#ff4040".color.darken(0.1)
        elif mouseR.hovered[]: "#ff4040".color.lighten(0.1)
        else: "#ff4040".color

      - UiText.new:
        this.centerIn parent
        text = "click me"
        font = typeface.withSize(14)
        color = color(1, 1, 1)

      - MouseArea.new as mouseR:
        this.fill parent
        cursor = BuiltinCursor.pointingHand

        on this.clicked:
          clicks[] = clicks[] + 1

    - UiRect.new:
      w = 120
      h = 40
      radius = 20
      color = binding:
        if mouse.pressed[]: "#4040ff".color.darken(0.1)
        elif mouse.hovered[]: "#4040ff".color.lighten(0.1)
        else: "#4040ff".color

      - MouseArea.new as mouse:
        this.fill parent

    - UiText.new:
      text := "clicks: " & $clicks[]
      font = typeface.withSize(13)

openInspector win
run win
