# note: incomplete

import unittest, sugar
import siwin
import sigui

type
  Switch* = ref object of Uiobj
    enabled*: Property[bool] = true.property
    isOn*: Property[bool]
    color*: Property[Col] = color(0, 0, 0).property

method init*(this: Switch) =
  if this.initialized: return
  procCall this.super.init()
  
  this.isOn.changed.connectTo this, val:
    echo "isOn changed: ", val

  this.makeLayout:
    this.w[] = 40
    this.h[] = 20

    - MouseArea() as mouse:
      this.fill(parent)
      this.mouseDownAndUpInside.connectTo root:
        if root.enabled[]:
          root.isOn[] = not root.isOn[]

      - UiRectStroke():
        this.fill(parent)
        this.binding radius: min(this.w[], this.h[]) / 2 - 2
        this.borderWidth[] = 2
        this.color[] = color(0.7, 0.7, 0.7)

        - UiRect():
          this.centerY = parent.center
          this.binding w: min(parent.w[], parent.h[]) - 8
          this.binding h: this.w[]
          this.binding radius: this.w[] / 2
          this.binding x:
            if root.isOn[]:
              parent.w[] - this.w[] - 4
            else:
              4'f32
          this.binding color: root.color[]

          - this.x.transition(0.4's):
            this.interpolation[] = outCubicInterpolation

    this.newChildsObject = mouse


test "todo app":
  type App = ref object of Uiobj
    tasks: seq[tuple[name: string, complete: Property[bool]]]
    tasksChanged: Event[void]

    layout: CustomProperty[Layout]

  let window = newOpenglWindow(size = ivec2(500, 800), title = "todos").newUiWindow

  const typefaceFile = staticRead "Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  window.makeLayout:
    this.clearColor = color(1, 1, 1)

    - App() as app

    - UiText() as text:
      this.centerX = parent.center
      this.y[] = 20
      this.font[] = newFont(typeface).buildIt:
        it.size = 72
      this.color[] = color(0.5, 0.5, 0.5)
      this.text[] = "todos"
    
    - UiRectStroke() as taskAdder:
      this.fillHorizontal(parent, 20)
      this.h[] = 40
      this.top = text.bottom + 20
      this.color[] = color(0.5, 0.5, 0.5)
      this.radius[] = 5
      
      # - UiTextArea():
      #   this.fill(parent, 4, 2)
      #   this.text[] = "sample task"
      #   this.textObj[].font[] = newFont(typeface).buildIt:
      #     it.size = 32
      - UiText() as taskName:
        this.centerY = parent.center
        this.left = parent.left + 10
        this.text[] = "sample task"
        this.font[] = newFont(typeface).buildIt:
          it.size = 32
      
      - UiRect() as addTask:
        this.right = parent.right - 5
        this.fillVertical(parent, 4)
        this.binding w: this.h[]
        this.binding color:
          if mouse.pressed[]: color(0.43, 0.15, 0.76).lighten(0.1)
          elif mouse.hovered[]: color(0.43, 0.15, 0.76).lighten(0.2)
          else: color(0.43, 0.15, 0.76)
        this.radius[] = 5

        - this.color.transition(0.4's):
          this.interpolation[] = outCubicInterpolation

        - UiText():
          this.centerIn parent
          this.text[] = "+"
          this.font[] = newFont(typeface).buildIt:
            it.size = 32
          this.color[] = color(1, 1, 1)

        - MouseArea() as mouse:
          this.fill parent
          this.mouseDownAndUpInside.connectTo this:
            app.tasks.add((name: taskName.text[], complete: false.property))
            app.tasksChanged.emit()

    app.layout --- Layout():
      this.fillHorizontal(parent, 20)
      this.bottom = parent.bottom - 20
      this.top = taskAdder.bottom + 20

      this.orientation[] = vertical
      this.spacing[] = 0

      for i in 0..app.tasks.high:  # todo: better loops support
        capture i, app, this:
          template task: auto = app.tasks[i]

          this.makeLayout:
            - UiText():
              this.text[] = task.name
              
              this.binding font:
                newFont(typeface).buildIt:
                  it.size = 24
                  it.strikethrough = task.complete[]
              
              this.binding color:
                if mouse.pressed[]: color(0.2, 0.2, 0.2)
                elif mouse.hovered[]: color(0.4, 0.4, 0.4)
                else: color(0, 0, 0)

              - MouseArea() as mouse:
                this.fill parent
                this.mouseDownAndUpInside.connectTo this:
                  task.complete[] = not task.complete[]
              
              - Switch():
                this.left = parent.right + 10
                this.centerY = parent.center
                this.color[] = color(0.43, 0.15, 0.76)
                
                this.binding isOn: task.complete[]
                this.bindingProperty task.complete: this.isOn[]
    
    app.tasksChanged.connectTo app:
      app.layout[] = Layout()

  run window.siwinWindow
