import unittest
import sigui

test "styles":
  let window = newUiWindow(size = ivec2(1280, 720), title = "styles")
  
  const typefaceFile = staticRead "Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  let darkTheme = makeStyle:
    UiText:
      font = typeface.withSize(24)
      color = "ffffff"
    
    UiRect:
      color = "303030"
      radius = 5

      - UiText.new:
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

      - UiText.new:
        this.centerIn parent
        text = "this should not be visible"
        color = "808080"


  window.makeLayout:
    this.clearColor = "202020"

    - Styler.new:
      this.fill parent
      style = lightTheme
      style = darkTheme
      

      - UiRect.new:
        x = 20
        y = 20
        w = 200
        h = 100

        - UiRect.new:
          this.centerIn root
          w = 50
          h = 50
      
      - UiText.new:
          bottom = parent.bottom
          text = "text with changed font"
          font = typeface.withSize(16)
    
    - UiRect.new:
      right = parent.right
      bottom = parent.bottom
      w = 100
      h = 50
    


  run window
