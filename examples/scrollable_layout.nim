import sigui, siwin, chroma


let win = newSiwinGlobals().newOpenglWindow(title = "sigui scroll area example").newUiRoot

makeLayout win:
  clearColor = "ffffff".color

  - UiRect.new:
    this.fill parent, 10
    radius = 10
    color = "c1c1c1".color

    - ScrollArea.new:
      this.fill parent

      this.horizontalScrollbarObj[].UiRect.color[] = "202020".color

      - Layout.col:
        this.fillHorizontal parent, 10
        gap = 10
        align = center
        wrapHugContent = false

        - LayoutGap.new: h = 10

        for i in 0..15:
          if i in [5, 11]:
            - LayoutGap.new: h = 2

          - UiRect.new:
            radius = 10
            w = binding:
              if i in [3, 7]: parent.w[] * 0.9
              else: parent.w[]
            h =
              if i in [2, 8]: 120
              else: 50

            let mainColor = rgba(66, 177, 44, 197).to(Color).spin(i.toFloat * 50)

            - MouseArea.new as mouse:
              this.fill parent
            
            color = binding:
              if mouse.pressed[]: mainColor.darken(0.2)
              elif mouse.hovered[]: mainColor.lighten(0.1)
              else: mainColor
            
            - this.color.transition(0.2's):
              easing = outSquareEasing
        
        - LayoutGap.new: h = 10



run win.siwinWindow

