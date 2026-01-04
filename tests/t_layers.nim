import unittest
import sigui

test "layers":
  let window = newUiWindow(size = ivec2(1280, 720), title = "layers")
  
  const typefaceFile = staticRead "Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  window.makeLayout:
    this.clearColor = color(1, 1, 1)

    - Styler.new:
      this.fill parent
      style = makeStyle:
        UiText:
          font = typeface.withSize(24)

      - UiText.new as nonClipped_text:
        centerX = nonClipped_rect.center
        top = parent.top + 20
        text = "non-clipped"
        this.fontSize = 32

      - UiText.new as clipped_text:
        centerX = clipped_rect.center
        top = parent.top + 20
        text = "clipped"
        this.fontSize = 32
      
      - UiText.new:
        left = parent.left + 20
        bottom = parent.bottom - 10
        text = "*not exacly parent, since object is in larger hierarchy: [ ClipRect ] > UiRect > Layout > this"
        this.fontSize = 16

      - Layout.new:
        left = parent.left + 20
        right = parent.right - 20
        top = nonClipped_text.bottom + 20
        bottom = parent.bottom - 40
        fillWithSpaces = true
        
        - UiRect.new as nonClipped_rect:
          w = 300
          h = binding: parent.h[]
          
          radius = 10
          color = color(0.7, 0.7, 0.7)

          - MouseArea.new:
            this.fill(parent)
            on this.mouseDownAndUpInside: echo "non-clipped (itself)"
        
          - Layout.new:
            this.fillVertical(parent, 20)
            left = parent.left + 20
            orientation = vertical
            fillWithSpaces = true

            - UiRect.new as ncr_a:
              h = 80
              w = 500

              radius = 10
              color = color(0.3, 0.3, 1)

              - MouseArea.new:
                this.fill(parent)
                on this.mouseDownAndUpInside: echo "non-clipped -> no modifications"

              - UiText.new:
                centerY = parent.center
                left = parent.left + 20
                color = color(1, 1, 1)
                text = "no modifications"
            
            - UiRect.new:
              layer = after nonClipped_rect

              h = 80
              w = 500

              radius = 10
              color = color(0.25, 0.25, 0.85)

              - MouseArea.new:
                this.fill(parent)
                on this.mouseDownAndUpInside: echo "non-clipped -> after parent"

              - UiText.new:
                centerY = parent.center
                left = parent.left + 20
                color = color(1, 1, 1)
                text = "after parent*"
            
            - UiRect.new:
              layer = before nonClipped_rect

              h = 80
              w = 500

              radius = 10
              color = color(0.2, 0.2, 0.7)

              - MouseArea.new:
                this.fill(parent)
                on this.mouseDownAndUpInside: echo "non-clipped -> before parent"

              - UiText.new:
                centerY = parent.center
                right = parent.right - 20
                color = color(1, 1, 1)
                text = "before parent*"

        - ClipRect.new as clipped_rect:
          w = 300
          h = binding: parent.h[]
          
          radius = 10

          - MouseArea.new:
            this.fill(parent)
            on this.mouseDownAndUpInside: echo "clipped (itself)"

          - UiRect.new:
            this.fill parent
            color = color(0.7, 0.7, 0.7)
          
            - Layout.new:
              top = parent.top + 30
              bottom = parent.bottom - 10
              left = parent.left - 220
              orientation = vertical
              fillWithSpaces = true

              - UiRect.new:
                h = 80
                w = 500

                radius = 10
                color = color(0.3, 1, 0.3)

                - MouseArea.new:
                  this.fill(parent)
                  on this.mouseDownAndUpInside: echo "clipped -> no modifications"

                - UiText.new:
                  centerY = parent.center
                  right = parent.right - 20
                  text = "no modifications"
              
              - UiRect.new:
                layer = after clipped_rect

                h = 80
                w = 500

                radius = 10
                color = color(0.25, 0.85, 0.25)

                - MouseArea.new:
                  this.fill(parent)
                  on this.mouseDownAndUpInside: echo "clipped -> after parent"

                - UiText.new:
                  centerY = parent.center
                  left = parent.left + 20
                  text = "after parent*"
              
              - UiRect.new:
                layer = before clipped_rect

                h = 80
                w = 500

                this.radius[] = 10
                this.color[] = color(0.2, 0.7, 0.2)

                - MouseArea.new:
                  this.fill(parent)
                  on this.mouseDownAndUpInside: echo "clipped -> before parent"

                - UiText.new:
                  centerY = parent.center
                  left = parent.left + 20
                  text = "before parent*"

  run window
