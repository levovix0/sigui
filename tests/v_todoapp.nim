# note: incomplete

import unittest
import sigui
import v_customComponent

type
  App = ref object of Uiobj
    tasks: seq[tuple[name: string, complete: Property[bool]]]
    tasksChanged: Event[void]

    layout: ChangableChild[Layout]

registerComponent App



test "todo app":
  let window = newUiWindow(size = ivec2(500, 800), title = "todos")

  const typefaceFile = staticRead "Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  window.makeLayout:
    this.clearColor = color(1, 1, 1)

    - App() as app

    - UiText(text = "todos") as text:
      centerX = parent.center
      y = 20
      color = color(0.5, 0.5, 0.5)
      font = typeface.withSize(72)
    
    - UiRectBorder(color = color(0.5, 0.5, 0.5), radius = 5) as taskAdder:
      this.fillHorizontal(parent, 20)
      h = 40
      top = text.bottom + 20
      
      - TextArea(text = "sample task") as taskName:
        this.fill(parent, 4, 2)
        right = addTask.left - 10
        
        + this.textObj:
          font = typeface.withSize(32)

        this.onKeyDown enter:
          mouse.clicked.emit()
      
      - UiRect(radius = 5) as addTask:
        right = parent.right - 5
        this.fillVertical(parent, 4)
        w := this.h[]
        
        color = binding:
          if mouse.pressed[]: color(0.43, 0.15, 0.76).lighten(0.1)
          elif mouse.hovered[]: color(0.43, 0.15, 0.76).lighten(0.2)
          else: color(0.43, 0.15, 0.76)

        - this.color.transition(0.4's):
          easing = outCubicEasing

        - UiText(text = "+"):
          this.centerIn parent
          font = typeface.withSize(32)
          color = color(1, 1, 1)

        - MouseArea(fill parent) as mouse:
          on this.clicked:
            if taskName.text[] == "": return
            app.tasks.add((name: taskName.text[], complete: false.property))
            app.tasksChanged.emit()
            taskName.pushState()
            taskName.text[] = ""

    - ScrollArea(fillHorizontal(parent, 20)):
      bottom = parent.bottom - 20
      top = taskAdder.bottom + 20

      app.layout --- Layout():
        <--- {update}: app.tasksChanged[]
        this.col(gap = 5)

        w = binding: parent.w[]

        for i in 0..app.tasks.high:
          template task: auto = app.tasks[i]

          - Layout.row(gap = 10) as taskRow:
            align = center

            - Switch(isOn: task.complete[].property):
              color = color(0.43, 0.15, 0.76)

              isOn := task.complete[]
              this.bindingValue task.complete[]: this.isOn[]

            - UiText(text = task.name):
              font = binding:
                let it = typeface.withSize(24)
                it.strikethrough = task.complete[]
                it

              color = binding:
                if mouse.pressed[]: color(0.2, 0.2, 0.2)
                elif mouse.hovered[]: color(0.4, 0.4, 0.4)
                else: color(0, 0, 0)

              - MouseArea(fill parent) as mouse:
                on this.clicked:
                  task.complete[] = not task.complete[]

            - UiRectBorder(radius = 5) as deleteTask:
              w = 30; h = 30
              
              color = binding:
                if delMouse.pressed[]: color(0.83, 0.17, 0.17).lighten(0.1)
                elif delMouse.hovered[]: color(0.83, 0.17, 0.17).lighten(0.2)
                else: color(0.83, 0.17, 0.17)

              - this.color.transition(0.4's):
                easing = outCubicEasing

              - UiText(text = "×"):
                this.centerIn parent
                font = typeface.withSize(24)
                color = color(0, 0, 0)

              - MouseArea(fill parent) as delMouse:
                on this.clicked:
                  # todo: "data model" for ChangableChild and it's deletion and insertion animations
                  app.layout[].animateOnDelete(taskRow.x[], taskRow.x[] - taskRow.w[], 0.2's, outCubicEasing)
                  for x in app.layout[].childs:
                    if x != taskRow:
                      x.visibility[] = Visibility.hidden
                  app.tasks.delete(i)
                  app.tasksChanged.emit()

  run window
