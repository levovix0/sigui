import unittest
import siwin
import sigui

test "layers":
  let window = newOpenglWindow(size = ivec2(1280, 720), title = "layers").newUiWindow
  
  const typefaceFile = staticRead "Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)
  globalDefaultFont = typeface.withSize(24)

  window.makeLayout:
    this.clearColor = color(1, 1, 1)

    - UiText() as nonClipped_text:
      centerX = nonClipped_rect.center
      top = parent.top + 20
      text = "non-clipped"
      this.fontSize = 32

    - UiText() as clipped_text:
      centerX = clipped_rect.center
      top = parent.top + 20
      text = "clipped"
      this.fontSize = 32
    
    - UiText():
      left = parent.left + 20
      bottom = parent.bottom - 10
      text = "*not exacly parent, since object is in larger hierarchy: [ ClipRect ] > UiRect > Layout > this"
      this.fontSize = 16

    - Layout():
      left = parent.left + 20
      right = parent.right - 20
      top = nonClipped_text.bottom + 20
      bottom = parent.bottom - 40
      fillWithSpaces = true
      
      - UiRect() as nonClipped_rect:
        w = 300
        this.binding h: parent.h[]
        
        radius = 10
        color = color(0.7, 0.7, 0.7)
      
        - Layout():
          this.fillVertical(parent, 20)
          left = parent.left + 20
          orientation = vertical
          fillWithSpaces = true

          - UiRect() as ncr_a:
            h = 80
            w = 500

            radius = 10
            color = color(0.3, 0.3, 1)

            - UiText():
              centerY = parent.center
              left = parent.left + 20
              color = color(1, 1, 1)
              text = "no modifications"
          
          - UiRect():
            drawLayer = after nonClipped_rect

            h = 80
            w = 500

            radius = 10
            color = color(0.3, 0.3, 1)

            - UiText():
              centerY = parent.center
              left = parent.left + 20
              color = color(1, 1, 1)
              text = "after parent*"
          
          - UiRect():
            drawLayer = before nonClipped_rect

            h = 80
            w = 500

            radius = 10
            color = color(0.3, 0.3, 1)

            - UiText():
              centerY = parent.center
              right = parent.right - 20
              color = color(1, 1, 1)
              text = "before parent*"

      - ClipRect() as clipped_rect:
        w = 300
        this.binding h: parent.h[]
        
        radius = 10

        - UiRect():
          this.fill parent
          color = color(0.7, 0.7, 0.7)
        
          - Layout():
            top = parent.top + 30
            bottom = parent.bottom - 10
            left = parent.left - 220
            orientation = vertical
            fillWithSpaces = true

            - UiRect():
              h = 80
              w = 500

              radius = 10
              color = color(0.3, 1, 0.3)

              - UiText():
                centerY = parent.center
                right = parent.right - 20
                text = "no modifications"
            
            - UiRect():
              drawLayer = after clipped_rect

              h = 80
              w = 500

              radius = 10
              color = color(0.3, 1, 0.3)

              - UiText():
                centerY = parent.center
                left = parent.left + 20
                text = "after parent*"
            
            - UiRect():
              drawLayer = before clipped_rect

              h = 80
              w = 500

              this.radius[] = 10
              this.color[] = color(0.3, 1, 0.3)

              - UiText():
                centerY = parent.center
                left = parent.left + 20
                text = "before parent*"

  run window.siwinWindow
