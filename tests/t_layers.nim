import unittest
import siwin
import sigui

test "layers":
  let window = newOpenglWindow(size = ivec2(1280, 720), title = "layers").newUiWindow
  
  const typefaceFile = staticRead "Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)
  globalDefaultFont = newFont(typeface).buildIt:
    it.size = 24

  window.makeLayout:
    this.clearColor = color(1, 1, 1)

    - UiText() as nonClipped_text:
      this.centerX = nonClipped_rect.center
      this.top = parent.top + 20
      this.text[] = "non-clipped"
      this.fontSize = 32

    - UiText() as clipped_text:
      this.centerX = clipped_rect.center
      this.top = parent.top + 20
      this.text[] = "clipped"
      this.fontSize = 32
    
    - UiText():
      this.left = parent.left + 20
      this.bottom = parent.bottom - 10
      this.text[] = "*not exacly parent, since object is in larger hierarchy: [ ClipRect ] > UiRect > Layout > this"
      this.fontSize = 16

    - Layout():
      this.left = parent.left + 20
      this.right = parent.right - 20
      this.top = nonClipped_text.bottom + 20
      this.bottom = parent.bottom - 40
      this.fillWithSpaces[] = true
      
      - UiRect() as nonClipped_rect:
        this.w[] = 300
        this.binding h: parent.h[]
        
        this.radius[] = 10
        this.color[] = color(0.7, 0.7, 0.7)
      
        - Layout():
          this.fillVertical(parent, 20)
          this.left = parent.left + 20
          this.orientation[] = vertical
          this.fillWithSpaces[] = true

          - UiRect() as ncr_a:
            this.h[] = 80
            this.w[] = 500

            this.radius[] = 10
            this.color[] = color(0.3, 0.3, 1)

            - UiText():
              this.centerY = parent.center
              this.left = parent.left + 20
              this.color[] = color(1, 1, 1)
              this.text[] = "no modifications"
          
          - UiRect():
            this.drawLayer = after nonClipped_rect

            this.h[] = 80
            this.w[] = 500

            this.radius[] = 10
            this.color[] = color(0.3, 0.3, 1)

            - UiText():
              this.centerY = parent.center
              this.left = parent.left + 20
              this.color[] = color(1, 1, 1)
              this.text[] = "after parent*"
          
          - UiRect():
            this.drawLayer = before nonClipped_rect

            this.h[] = 80
            this.w[] = 500

            this.radius[] = 10
            this.color[] = color(0.3, 0.3, 1)

            - UiText():
              this.centerY = parent.center
              this.right = parent.right - 20
              this.color[] = color(1, 1, 1)
              this.text[] = "before parent*"

      - ClipRect() as clipped_rect:
        this.w[] = 300
        this.binding h: parent.h[]
        
        this.radius[] = 10

        - UiRect():
          this.fill parent
          this.color[] = color(0.7, 0.7, 0.7)
        
          - Layout():
            this.top = parent.top + 30
            this.bottom = parent.bottom - 10
            this.left = parent.left - 220
            this.orientation[] = vertical
            this.fillWithSpaces[] = true

            - UiRect():
              this.h[] = 80
              this.w[] = 500

              this.radius[] = 10
              this.color[] = color(0.3, 1, 0.3)

              - UiText():
                this.centerY = parent.center
                this.right = parent.right - 20
                this.text[] = "no modifications"
            
            - UiRect():
              this.drawLayer = after clipped_rect

              this.h[] = 80
              this.w[] = 500

              this.radius[] = 10
              this.color[] = color(0.3, 1, 0.3)

              - UiText():
                this.centerY = parent.center
                this.left = parent.left + 20
                this.text[] = "after parent*"
            
            - UiRect():
              this.drawLayer = before clipped_rect

              this.h[] = 80
              this.w[] = 500

              this.radius[] = 10
              this.color[] = color(0.3, 1, 0.3)

              - UiText():
                this.centerY = parent.center
                this.left = parent.left + 20
                this.text[] = "before parent*"

  run window.siwinWindow
