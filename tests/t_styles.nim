import unittest
import siwin
import sigui

test "styles":
  let window = newOpenglWindow(size = ivec2(1280, 720), title = "styles").newUiWindow
  
  const typefaceFile = staticRead "Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  let darkTheme = makeStyle:
    UiText:
      font = typeface.withSize(24)
      color = "ffffff"
    
    UiRect:
      color = "303030"
      radius = 5

      - UiText():
        this.centerIn parent
        text = "rect"
        color = "808080"

  let lightTheme = makeStyle:
    apply darkTheme

    UiText:
      color = "000000"
    
    UiRect:
      color = "e0e0e0"
      radius = 5

      - UiText():
        this.centerIn parent
        text = "this should not be visible"
        color = "808080"


  window.makeLayout:
    this.clearColor = "202020"

    - Styler():
      this.fill parent
      style = lightTheme
      style = darkTheme
      

      - UiRect():
        x = 20
        y = 20
        w = 200
        h = 100

        - UiRect():
          this.centerIn root
          w = 50
          h = 50
      
      - UiText():
          bottom = parent.bottom
          text = "text with changed font"
          font = typeface.withSize(16)
    
    - UiRect():
      right = parent.right
      bottom = parent.bottom
      w = 100
      h = 50
    


  run window.siwinWindow
