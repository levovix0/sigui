# note: incomplete

import unittest
import siwin
import sigui
import t_customComponent

type App = ref object of Uiobj
  tasks: seq[tuple[name: string, complete: Property[bool]]]
  tasksChanged: Event[void]

  layout: CustomProperty[Layout]

registerComponent App


test "todo app":
  let window = newOpenglWindow(size = ivec2(500, 800), title = "todos").newUiWindow

  const typefaceFile = staticRead "Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  window.makeLayout:
    this.clearColor = color(1, 1, 1)

    - App() as app

    - UiText() as text:
      centerX = parent.center
      y = 20
      font = typeface.withSize(72)
      color = color(0.5, 0.5, 0.5)
      text = "todos"
    
    - UiRectBorder() as taskAdder:
      this.fillHorizontal(parent, 20)
      h = 40
      top = text.bottom + 20
      color = color(0.5, 0.5, 0.5)
      radius = 5
      
      - TextArea() as taskName:
        this.fill(parent, 4, 2)
        right = addTask.left - 10
        text = "sample task"
        this.textObj[].font[] = typeface.withSize(32)
      
      - UiRect() as addTask:
        right = parent.right - 5
        this.fillVertical(parent, 4)
        this.binding w: this.h[]
        this.binding color:
          if mouse.pressed[]: color(0.43, 0.15, 0.76).lighten(0.1)
          elif mouse.hovered[]: color(0.43, 0.15, 0.76).lighten(0.2)
          else: color(0.43, 0.15, 0.76)
        radius = 5

        - this.color.transition(0.4's):
          easing = outCubicEasing

        - UiText():
          this.centerIn parent
          text = "+"
          font = typeface.withSize(32)
          color = color(1, 1, 1)

        - MouseArea() as mouse:
          this.fill parent
          this.mouseDownAndUpInside.connectTo this:
            app.tasks.add((name: taskName.text[], complete: false.property))
            app.tasksChanged.emit()

    - ClipRect():
      this.fillHorizontal(parent, 20)
      bottom = parent.bottom - 20
      top = taskAdder.bottom + 20

      - MouseArea():
        this.fill parent

        - Uiobj():
          this.binding w: parent.w[]

          - this.y.transition(0.2's):
            easing = outSquareEasing

          var targetY = 0'f32.property
          this.binding y: targetY[]

          parent.scrolled.connectTo this, delta:
            targetY[] = (targetY[] - delta.y * 56).min(0).max(-(app.layout[].h[] - 56).max(0))
            redraw this

          app.layout --- Layout():
            this.binding w: parent.w[]

            orientation = vertical
            spacing = 0
            hugContent = true

            for i in 0..app.tasks.high:
              template task: auto = app.tasks[i]

              - UiText():
                this.text[] = task.name
                
                this.binding font:
                  let it = typeface.withSize(24)
                  it.strikethrough = task.complete[]
                  it
                
                this.binding color:
                  if mouse.pressed[]: color(0.2, 0.2, 0.2)
                  elif mouse.hovered[]: color(0.4, 0.4, 0.4)
                  else: color(0, 0, 0)

                - MouseArea() as mouse:
                  this.fill parent
                  this.mouseDownAndUpInside.connectTo this:
                    task.complete[] = not task.complete[]
                
                - Switch(isOn: task.complete[].property):
                  left = parent.right + 10
                  centerY = parent.center
                  color = color(0.43, 0.15, 0.76)
                  
                  this.binding isOn: task.complete[]
                  this.bindingValue task.complete[]: this.isOn[]
      
    app.tasksChanged.connectTo app:
      app.layout[] = Layout()

  run window.siwinWindow
