import std/[unittest, times, strformat]
import siwin, sigui/[uibase, uiobj, layouts, mouseArea, scrollArea, styles]

const count {.intdefine.} = 1000

test "layout benchmark":
  let window = newSiwinGlobals().newOpenglWindow(size = ivec2(600, 720), title = "layouts benchmark").newUiWindow

  const typefaceFile = staticRead "Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  window.makeLayout:
    clearColor = "202020".litToColor.static
    
    - Styler.new:
      this.fill(parent)

      style = makeStyle:
        UiText:
          font = typeface.withSize(16)
          color = "ffffff".litToColor.static

      var manyButtons: ChangableChild[Layout]
      var generate = false

      - UiRect.new:
        this.fillHorizontal(parent, 10)
        h = 30
        y = 10
        radius = 5
        color = binding:
          if recreate.pressed[]: "282828".litToColor.static
          elif recreate.hovered[]: "404040".litToColor.static
          else: "303030".litToColor.static

        - MouseArea.new as recreate:
          this.fill(parent)

          on this.mouseDownAndUpInside:
            generate = true
            let startTime = now()
            manyButtons[] = Layout.new
            let endTime = now()
            recreate_text.text[] = &"created {count} buttons in {(endTime - startTime).inMilliseconds} ms"

        
        - UiText.new as recreate_text:
          this.centerIn(parent)
          text = &"create {count} buttons"
          


      - ScrollArea.new:
        this.fill(parent, 10)
        this.top = recreate.bottom + 10

        this.verticalScrollbarObj[].UiRect.color[] = "808080".litToColor.static

        manyButtons --- Layout.new:
          if generate:
            this.fillHorizontal(parent)
            
            orientation = vertical
            gap = 10
            fillContainer = true

            for i in 0 ..< count:
              - UiRect.new:
                h = 30
                radius = 5
                color = binding:
                  if mouse.pressed[]: "282828".litToColor.static
                  elif mouse.hovered[]: "383838".litToColor.static
                  else: "101010".litToColor.static
                
                - UiText.new as txt:
                  this.centerIn(parent)
                  text = "Click me!"

                - MouseArea.new as mouse:
                  this.fill(parent)

                  on this.mouseDownAndUpInside:
                    txt.text[] = &"Clicked {i}!"


  run window.siwinWindow
