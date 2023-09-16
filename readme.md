
# Custom components
```nim
type
  Button* = ref object of Uiobj
    clicked*: Event[void]
    text*: Property[string]


proc newButton*: Button =
  result = Button()

  result.makeLayout:
    - newUiRect():
      this.anchors.fill parent
      this.color[] = color(0.2, 0.2, 0.2)
      this.radius[] = 5
    
    - newUiText():
      this.anchors.centerIn parent
      this.binding text: parent.text[]
    
    - newMouseArea():
      this.anchors.fill parent
      
      this.mouseDownThenUpInside.connectTo root:
        root.clicked.emit()


# somethere in app layout...
  - newButton():
    this.text[] = "Hello"
    
    this.clicked.connectTo this:
      this.text[] = "Button"

```
