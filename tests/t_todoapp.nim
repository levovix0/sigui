# note: incomplete

import unittest
import siwin
import sigui
import t_customComponent

type
  App = ref object of Uiobj
    tasks: seq[tuple[name: string, complete: Property[bool]]]
    tasksChanged: Event[void]

    layout: ChangableChild[Layout]

  DestroyLoggerInner = object
    message: string

  DestroyLogger = ref object of Uiobj
    inner: DestroyLoggerInner

registerComponent App


proc `=destroy`(x: DestroyLoggerInner) =
  if x.message != "":
    echo x.message


test "todo app":
  let window = newSiwinGlobals().newOpenglWindow(size = ivec2(500, 800), title = "todos").newUiWindow

  const typefaceFile = staticRead "Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  window.makeLayout:
    this.clearColor = color(1, 1, 1)

    - App.new as app

    - UiText.new as text:
      centerX = parent.center
      y = 20
      font = typeface.withSize(72)
      color = color(0.5, 0.5, 0.5)
      text = "todos"
    
    - UiRectBorder.new as taskAdder:
      this.fillHorizontal(parent, 20)
      h = 40
      top = text.bottom + 20
      color = color(0.5, 0.5, 0.5)
      radius = 5
      
      - TextArea.new as taskName:
        this.fill(parent, 4, 2)
        right = addTask.left - 10
        text = "sample task"
        this.textObj[].font[] = typeface.withSize(32)

        this.onKeyDown enter:
          mouse.mouseDownAndUpInside.emit()
      
      - UiRect.new as addTask:
        right = parent.right - 5
        this.fillVertical(parent, 4)
        w := this.h[]
        
        radius = 5
        color = binding:
          if mouse.pressed[]: color(0.43, 0.15, 0.76).lighten(0.1)
          elif mouse.hovered[]: color(0.43, 0.15, 0.76).lighten(0.2)
          else: color(0.43, 0.15, 0.76)

        - this.color.transition(0.4's):
          easing = outCubicEasing

        - UiText.new:
          this.centerIn parent
          text = "+"
          font = typeface.withSize(32)
          color = color(1, 1, 1)

        - MouseArea.new as mouse:
          this.fill parent

          on this.mouseDownAndUpInside:
            if taskName.text[] == "": return
            app.tasks.add((name: taskName.text[], complete: false.property))
            app.tasksChanged.emit()
            taskName.pushState()
            taskName.text[] = ""

    - ScrollArea.new:
      this.fillHorizontal(parent, 20)
      bottom = parent.bottom - 20
      top = taskAdder.bottom + 20

      app.layout --- Layout.new:
        <--- Layout(): app.tasksChanged[]

        this.binding w: parent.w[]

        orientation = vertical
        gap = 5

        for i in 0..app.tasks.high:
          template task: auto = app.tasks[i]

          - DestroyLogger.new as logger:
            this.inner.message = "destroyed: " & $i

          - Layout.new:
            spacing = 10
            align = center
            
            - Switch(isOn: task.complete[].property):
              color = color(0.43, 0.15, 0.76)
              
              isOn := task.complete[]
              this.bindingValue task.complete[]: this.isOn[]

            - UiText.new:
              text = task.name
              
              this.binding font:
                let it = typeface.withSize(24)
                it.strikethrough = task.complete[]
                it
              
              this.binding color:
                if mouse.pressed[]: color(0.2, 0.2, 0.2)
                elif mouse.hovered[]: color(0.4, 0.4, 0.4)
                else: color(0, 0, 0)

              - MouseArea.new as mouse:
                this.fill parent
                on this.mouseDownAndUpInside:
                  task.complete[] = not task.complete[]
                  echo "made sure ", logger.inner.message, " works"

  run window.siwinWindow
