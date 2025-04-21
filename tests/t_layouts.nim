import std/[unittest]
import siwin, sigui/[uibase, uiobj, layouts]


test "layouts":
  let window = newSiwinGlobals().newOpenglWindow(size = ivec2(1280, 720), title = "layouts").newUiWindow

  window.makeLayout:
    clearColor = color(1, 1, 1)

    - Layout.row(gap = 16):
      this.fill(parent, 16)
      
      fillContainer = true

      - UiRect.new:
        w = 300
        color = "c0c0c0"
      
      - InLayout.new:
        grow = 1
        
        on this.w.changed:
          echo "w: ", this.w[], " (x: ", this.x[], ")"
        on this.h.changed:
          echo "h: ", this.h[], " (y: ", this.y[], ")"

        - UiRect.new:
          color = "808080"
          h = 50


  run window.siwinWindow
