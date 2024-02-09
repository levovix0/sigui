# note: incomplete

import unittest, sugar
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
      
      # - UiTextArea():
      #   this.fill(parent, 4, 2)
      #   this.text[] = "sample task"
      #   this.textObj[].font[] = typeface.withSize(32)
      - UiText() as taskName:
        centerY = parent.center
        left = parent.left + 10
        text = "sample task"
        font = typeface.withSize(32)
      
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
          this.interpolation[] = outCubicInterpolation

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

    app.layout --- Layout():
      this.fillHorizontal(parent, 20)
      bottom = parent.bottom - 20
      top = taskAdder.bottom + 20

      orientation = vertical
      spacing = 0

      for i in 0..app.tasks.high:  # todo: better loops support
        capture i, app, this:
          template task: auto = app.tasks[i]

          this.makeLayout:
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
              
              - Switch():
                left = parent.right + 10
                centerY = parent.center
                color = color(0.43, 0.15, 0.76)
                
                this.binding isOn: task.complete[]
                this.bindingValue task.complete[]: this.isOn[]
    
    app.tasksChanged.connectTo app:
      app.layout[] = Layout()

  run window.siwinWindow
