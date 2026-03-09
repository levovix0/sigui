
import sigui

let win = newUiWindow()

win.makeLayout:
  this.clearColor = "#202020".color

  - UiRect.new:
    color = "#b65656ff".color.darken(0.2)
    x = 100; y = 100
    w = 200; h = 100


run win

