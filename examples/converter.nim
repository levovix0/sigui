import std/[strformat, strutils]
import pkg/[sigui, siwin, toscel]

let win = newUiWindow(size = ivec2(300, 200), title = "Temperature converter")

win.makeLayout:
  this.clearColor = color_bg

  - Layout.row as row:
    this.centerIn parent
    align = center
    gap = 10
    padding = 10

    - LineEdit.new as celsius:
      text = "5"
      on this.textArea.textEdited:
        try:
          let c = this.text[].parseFloat
          let f = c * (9.0 / 5.0) + 32.0
          farenheit.text[] = &"{f:.1f}"
        except:
          discard
    
    - UiText.new:
      font = font_default.withSize(14)
      text = "Celsius ="
      color = color_fg
    
    - LineEdit.new as farenheit:
      text = "41"
      on this.textArea.textEdited:
        try:
          let f = this.text[].parseFloat
          let c = (f - 32.0) / (9.0 / 5.0)
          celsius.text[] = &"{c:.1f}"
        except:
          discard
    
    - UiText.new:
      font = font_default.withSize(14)
      text = "Farenheit"
      color = color_fg
  
  win.siwinWindow.size = row.wh.ivec2


run win
