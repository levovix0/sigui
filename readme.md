# Sigui
<img alt="sigui" width="100%" src="http://levovix.ru:8000/docs/sigui/banner.png">
<p align="center">
  Pure Nim, easy to use and flexible UI framework.
</p>

*In active development*

Sigui is inspired by QtQuick.

Libraries to see also:
- [toscel](https://github.com/levovix0/toscel) - component library for sigui (buttons, labels, text edits, etc..)
- [siwin](https://github.com/levovix0/siwin) - window creation library
- [localize](https://github.com/levovix0/localize) - application translation library
- [pixie](https://github.com/treeform/pixie) - CPU drawing library
- [shady](https://github.com/treeform/shady) - GLSL shader generator from Nim functions

Related documentation:
- [Builtin components](documentation/components.md)


## Table of contents
1. [Examples](#Examples)
    * [Minimal](#Minimal)
    * [Basic](#Basic)
    * [Custom component](#Custom-component)
    * [File templates](#File-templates)
2. [Features](#Features)
    * [Events](#Events)
    * [Properties and bindings](#Properties-and-bindings)
    * [Ui Objects](#Ui-Objects)
    * [Signals](#Signals)
    * [Animations and transitions](#Animations-and-transitions)
    * [Layouts](#Layouts)
    * [makeLayout](#makeLayout)
    * [Anchors](#Anchors)
    * [Layers](#Layers)
3. [Builtin components](#Builtin-components)
    * [Text Area](#Text-Area)
4. [Interaction with other libraries](#Interaction-with-other-libraries)
    * [localize](#localize)

# Examples
see also: [tests](https://github.com/levovix0/sigui/tree/main/tests)

## Minimal

```nim
import sigui

let win = newUiWindow()

win.makeLayout:
  this.clearColor = "#202020".color

run win
```
window by default has no title, size (1280, 720), and opaque black background (clear) color

## Basic
https://github.com/levovix0/sigui/assets/53170138/9509e245-2701-4dba-8237-a83f480aa635
```nim
import sigui

let win = newUiWindow(size=ivec2(1280, 720), title="Hello sigui")

win.makeLayout:
  - UiRect.new:
    this.centerIn(parent)
    w = 100  # same as this.w[] = 100
    h := this.w[]  # same as this.bindingValue this.h[]: this.w[]

    var state = 0.property

    color = binding:  # same as this.bindingValue this.color[]:
      (
        case state[]
        of 0: color(1, 0, 0)
        of 1: color(0, 1, 0)
        else: color(0, 0, 1)
      ).lighten(if mouse.hovered[]: 0.3 else: 0)

    - this.color.transition(0.4's)

    - MouseArea.new as mouse:
      this.fill(parent)
      on this.mouseDownAndUpInside:
        state[] = (state[] + 1) mod 3
      this.cursor = BuiltinCursor.pointingHand

run win
```


## Custom component
Minimal example:
```nim
import sigui/[uibase]

type
  MyComponent* = ref object of Uiobj

registerComponent MyComponent

method init*(this: Switch) =
  procCall this.super.init()
```

https://github.com/levovix0/sigui/assets/53170138/409cb2a3-5299-48a6-b01e-d8b7bb951fbb
```nim
import sigui/[uibase, mouseArea, animations, dolars]

type
  Switch* = ref object of Uiobj
    enabled*: Property[bool] = true.property
    isOn*: Property[bool]
    color*: Property[Col] = color(0, 0, 0).property

registerComponent Switch


method init*(this: Switch) =
  procCall this.super.init()
  
  this.isOn.changed.connectTo this:
    echo this

  this.makeLayout:
    w = 40
    h = 20

    - MouseArea.new as mouse:
      this.fill(parent)
      this.mouseDownAndUpInside.connectTo root:
        if root.enabled[]:
          root.isOn[] = not root.isOn[]

      - UiRectBorder.new:
        this.fill(parent)
        this.binding radius: min(this.w[], this.h[]) / 2 - 2
        borderWidth = 2
        color = "aaa"

        - UiRect.new:
          centerY = parent.center
          w := min(parent.w[], parent.h[]) - 8
          h := this.w[]
          radius := this.w[] / 2
          x = binding:
            if root.isOn[]:
              parent.w[] - this.w[] - 4
            else:
              4'f32
          color := root.color[]

          - this.x.transition(0.4's):
            easing = outCubicEasing

    this.newChildsObject = mouse


when isMainModule:
  preview:
    this.clearColor = "#ffffff".color
    - Switch.new:
      this.margin = 20.allSides
```

## File templates

Create an empty file and type:
```nim
import sigui; refactor_siguiComponentFile(MyComponent)
```
then compile it with -d:refactor to create the minimal example in the file.

This is more useful for creating custom component skeletons

```nim
import sigui; refactor_siguiComponentFile(MyComponent)
```

```nim
import sigui; refactor_siguiShaderComponentFile(MyShaderComponent)
```

If you find yourself writing this often, consider using a shell script
```fish
function sigui-create
  echo "import sigui/uiobj; refactor_sigui"$argv[2]"("$argv[2..-1]")" > $argv[1] && nim c -d:refactor $argv[1]
end
```
```fish
sigui-create a.nim ShaderComponentFile
```

# Features
## Events
```nim
var event: Event[int]
var eventHandler: EventHandler

event.connect eventHandler, proc(e: int) =
  echo e

event.connectTo eventHandler, val:
  echo "another ", val

event.emit 10
```
Events can be connected to EventHandler or HasEventHandler object. note that Uiobj fits HasEventHandler concept.

Events can be disconnected
```nim
var e: Event[int]
var eh: EventHandler

# ...

disconnect e, eh  # disconnect all functions that was connected like connect(e, eh, ...)
disconnect e      # disconnect all functions that was connected to this event
disconnect eh     # disconnect all functions that was connected to this event handler
```
If you have a group of callbacks to diffirent events, that you periodically disconnect all at once, consider creating an EventHandler for this group.

You can check `event.hasHandlers` for optimizing if you need to do complex logic to emit event. Don't do work if no one notice!

## Properties and bindings
```nim
var x: Property[int]
var y = CustomProperty[int](
  get: proc(): int = 1
  set: proc(v:  int) = echo v
)
var eh: EventHandler

x.changed.connectTo eh:
  echo "x changes observed by event handler"

eh.bindingValue y[]: x[]

x[] = 10  # both "x changes observed by event handler" and "10"
echo y[]  # 1
```

`Property[T]` is container for T, wrapping variable into property  
`CustomProperty[T]` instead holds get and set closures  
`AnyProperty[T]` is concept:
```nim
type AnyProperty[T] = concept a, var v
  a[] is T
  v[] = T
  a.changed is Event[T]
  a{} is T
  v{} = T
```

`prop{}`/`prop{}=` can be used instead of `prop[]`/`prop[]=` to not emit changed event.

For regular `Property[T]`, `prop{}` returns `var T`. This is useful if you need to store sequences as properties:
```nim
var items: Property[seq[Property[int]]]

# ...

# adding an item
items{}.add 1.property
items.changed.emit()

# removing some items
items{}.delete 1, 5
items.changed.emit()

# just changing an item
items{}[2][] = 10
# we can emit changed here, but since items already stores Property, it should not be neccessary
```

`binding` macros macros group will automatically subscribe to all properties' change events if they are mentioned. It isn't magic, binding macro will determine if smth is property if you call `[]` on it (which is the get proc).

There is:
- `uiobj.binding prop: ...`: binds property that is field named `prop` inside `uiobj`
- `eh.bindingValue val: ...` binds to assignment to `val`
- `eh.bindingProc f: ...` bind to call f(eh, body). Useful for nim-like properties (image=, len=, etc.)

```nim
let this = Uiobj()
var otherProp: Property[float32]

this.binding x: max(this.y[], otherProp[])
```
will be translated to something like:
```nim
proc update_1() =
  this.x[] = max(this.y[], otherProp[])
update_1()
this.y.changed.connectTo this: update_1()
otherProp.changed.connectTo this: update_1()
```

## Ui Objects
```nim
type
  MyComponent = ref object of Uiobj
    myState*: Property[int]
    myInternalState: int

registerComponent MyComponent


method init*(this: MyComponent) =
  procCall this.super.init()

  this.myState.changed.connectTo this:
    this.myInternalState = this.myState[]

  this.makeLayout:
    - UiRect.new:
      this.fill parent

# ... in makeLayout
- MyComponent.new:
  # implicitly called init
  # ...
```
Ui object is viewable and temporary state container.

Components are usually implemented as Ui objects. It is good practice to use composition to make your own components.

Global position of child ui object is global position of its parent plus its x and y. Global position is position from top-left courner of window. All positions is counted in pixels.

Ui objects can receive signals.

## Signals
```nim
type
  MySignal = object of SubtreeSignal
    val: int

method recieve*(this: MyComponent, signal: Signal) =
  if signal of MySignal:
    echo signal.MySignal.val
    # note: not calling this.super.recieve(signal) to not send MySignal to childs of this object and not emit this.onSignal
  else:
    procCall this.super.recieve(signal)

# ...
obj.parentUiWindow.recieve MySignal(val: 10)
# or
obj.recieve MySignal(val: 10)

```
Signals is global "events", recieved by all ui objects in hierarchy. Window events is signals.

Signals are more useful than events when you need to control order in which signals are handled.

Ui objects also have onSignal event.

## Animations and transitions
Animation is just interpolation between 2 values over time and doing action using this value.

Transition is just animation, that is subscribed to property changing, and its action is changing property.

Interpolation modifier (which is function, that takes float between 0..1 and returns modified float value around 0..1) can be attached to animation via `anim.intermolation[]=`

Built-in interpolation modifiers:
- `linearInterpolation` (default)
- `outSquareInterpolation` and `outQubicInterpolation` - faster at start, slower at end
- `inSquareInterpolation` and `inQubicInterpolation` - slower at start, faster at end
- `outBounceInterpolation` - like outSquare, but goes above target value and back at end
- `inBounceInterpolation` - like inSquare, but goes under start value at start

## Layouts
*not to be confused with makeLayout macro*

simple layouts:
```nim
- Layout.col(gap = 10):  # positions elements vertically with gap between them, use Layout.row() for horizontal
  - UiRect.new:
    w = 20
    h = 20
    color = "#ff4040".color

  - UiRect.new:
    w = 30
    h = 10
    color = "#40ff40".color

  - UiRect.new:
    w = 10
    h = 30
    color = "#4040ff".color
```
![image](http://levovix.ru:8000/docs/sigui/simple%20layouts%20example.png)

layouts have many properties, see src/sigui/layouts.nim for all
```nim
- Layout.new:
  h = 720
  gap = 10
  wrapGap = 20
  orientation = vertical
  hugContent = false
  wrapHugContent = true
  fillWithSpaces = true
  consistentSpacing = true
  wrap = true
  elementsBeforeWrap = 3
  lengthBeforeWrap := this.w[]

  - UiRect.new:
    w = 20
    h = 30
  
  - InLayout.new:
    align = center

    - UiRect.new:
      w = 10
      h = 10

  - UiRect.new:
    w = 30
    w = 20
```

## makeLayout
Make layout is a macro, that transforms tree-structured (ui)object creation into nested closures

```nim
type
  MyComponent = ref object of Uiobj
    changableChild: ChangableChild[UiRect]

registerComponent MyComponent


let x = MyComponent.new
x.makeLayout:
  - UiRect.new:
    this.fill parent
    this.binding color: rect2.color[].darken(0.5)  # objects created and aliased using `as` can be referenced before declaration

    - UiRect.new as rect2:
      w = 20
      h = 30
      color = color(1, 1, 1)
    
      root.changableChild --- UiRect.new:
        # actions in this body will be executed when root.changableChild is changed
        this.fill(parent, 2, 4)
```

makeLayout will produce something like this:
```nim
block makeLayoutBlock_1:
  let
    root {.used.} = x  # object, passed as a parameter to makeLayout will be called root
    
    # forward declare objects, which got a name through `- ... as name`
    rect2 = new(UiRect)
  
  block initializationBlock_2:
    proc proc_1(parent: typeof(root.parent); this: typeof(root)) =
      # for each object, `this` is current object, `parent` is this.parent
      initIfNeeded(this)
      let tmp_1 = new(UiRect)
      addChild(this, tmp_1)

      block initializationBlock_3:
        proc proc_2(parent: typeof(this); this: typeof(tmp_1)) =
          initIfNeeded(this)
          fill(this, parent, 0.0)
          this.binding color: rect2.color[].darken(0.5)  # binding is another macro
          addChild(this, rect2)
          
          block initializationBlock_4:
            proc proc_3(parent: typeof(this); this: typeof(rect2)) =
              initIfNeeded(this)
              this.w[] = 20
              this.h[] = 30
              this.color[] = color(1, 1, 1, 1.0)
              
              block changableChildInitializationBlock_1:  # changable childs is created like this:
                root.changableChild = addChangableChild(this, new(UiRect))
                
                proc tmp_2(parent: typeof(this); this: typeof(root.changableChild[])) =
                  block initializationBlock_5:
                    proc (parent: typeof(parent); this: typeof(this)) =
                      initIfNeeded(this)
                      fill(this, parent, 2, 4)(parent, this)
                
                tmp_2(this, root.changableChild[])
                connect(root.changableChild.changed, this.eventHandler, proc () =
                  tmp_2(this, root.changableChild[]), {}
                )

            proc_3(this, rect2)

        proc_2(this, tmp_1)

    proc_1(root.parent, root)
```

makeLayout also provides some sugar
```nim
Uiobj.new.makeLayout:
  on this.x.changed:
    ## this.x.changed.connectTo this: ...
  
  - MouseArea.new:
    on this.grabbed[] == true:
      ## this.grabbed.changed.connectTo this:
      ##   if this.grabbed[] == true: ...
```

### changable childs
Changable childs could be used to re-build component tree on any event.
```nim
# ...in makeLaout macro...

var elements = ["first", "second"]
var elementsObj: ChangableChild[Layout]

elementsObj --- Layout.new:
  orientation = vertical
  gap = 10

  for i, element in elements:
    - TextArea.new:
      text = element

      on this.text.changed:
        elements[i] = this.text[]
  
  - InLayout.new:
    fillContainer = true

    - MouseArea.new:
      h = 20

      on this.mouseDownAndUpInside:
        elements.add "new"
        elementsObj[] = Layout.new  # re-build tree

      - UiText():
        this.centerIn parent
        text = "+"
```

The `<--- ctor: prop[]; event[]; ...` syntax can be used to re-build tree based on property changes
```nim
var elements = ["first", "second"].property

--- Layout.new:
  <--- Layout.new: elements[]

  # ...

  - InLayout.new:
    # ...

    - MouseArea.new:
      # ...

      this.mouseDownAndUpInside.connectTo this:
        elements{}.add "new"
        elements.changed.emit()

      # ...
```


## Anchors
![image](http://levovix.ru:8000/docs/sigui/anchors%20example.png)
*centering component is `this.centerIn parent`*
```nim
- UiRect.new:
  this.fill parent
  color = color(0, 1, 0)

  - UiRect.new as rect:
    left = parent.center  # same as this.left = parent.center
    right = parent.right
    bottom = parent.bottom - 10  # -i always means up/left and +i means down/right, even if theese all are bottom anchors
    color = color(1, 0, 0)
  
  - UiRect.new:
    centerX = rect.left
    centerY = parent.center + 1
    color = color(0, 0, 1)
```

## Layers
![image](http://levovix.ru:8000/docs/sigui/layers%20example.png)
Unlike other ui libs, sigui don't have z-indices. Instead, you can directly specify component `before`, `after` or `beforeChilds` your component should be rendered.
```nim
- UiRect.new:
  #...

  - UiRect.new as rect:
    drawLayer = before parent
  
- UiRect.new:
  drawLayer = after rect
```

## Custom shaders
![image](http://levovix.ru:8000/docs/sigui/example%20images/custom%20shader.png)

```nim
import shady

type ChessTiles = ref object of Uiobj
  tileSize: float

registerComponent ChessTiles


method draw*(this: ChessTiles, ctx: DrawContext) =
  this.drawBefore(ctx)
  if this.visibility == visible:
    let shader = ctx.makeShader:
      proc vert(
        gl_Position: var Vec4,
        pos: var Vec2,
        ipos: Vec2,
        transform: Uniform[Mat4],
        size: Uniform[Vec2],
        px: Uniform[Vec2],
      ) =
        # default sigui specific transformation to correct locate component on screen
        # and convert opengl's coordinate system (-1..1) to sigui's coordinate system (0..windowSize_inPixels)
        # out `pos` is component-local (0..componentSize_inPixels)
        transformation(gl_Position, pos, size, px, ipos, transform)
        # don't use it if you don't need it (and don't call `ctx.passTransform` if so)

      proc frag(
        glCol: var Vec4,
        pos: Vec2,
        tileSize: Uniform[float],
      ) =
        if (
          (pos.x - ((pos.x / (tileSize * 2)).floor * (tileSize * 2)) >= tileSize) ==
          (pos.y - ((pos.y / (tileSize * 2)).floor * (tileSize * 2)) >= tileSize)
        ):
          glCol = vec4(1, 1, 1, 1)
        else:
          glCol = vec4(0, 0, 0, 1)
      
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

    use shader.shader
    ctx.passTransform(shader, pos=(this.xy.posToGlobal(this.parent) + ctx.offset).round, size=this.wh.round, angle=0)
    shader.tileSize.uniform = this.tileSize
    
    draw ctx.rect
    
    glDisable(GlBlend)
  this.drawAfter(ctx)
```

## Styles
![image](http://levovix.ru:8000/docs/sigui/example%20images/styles.png)
```nim
const typefaceFile = staticRead "Roboto-Regular.ttf"
let typeface = parseTtf(typefaceFile)

- Styler.new:
  this.fill parent
  style = makeStyle:
    UiText:
      font = typeface.withSize(24)
      color = "ffffff"
    
    UiRect:
      color = "303030"
      radius = 5

      - UiText():
        this.centerIn parent
        text = "rect"
        color = "808080"
  

  - UiRect.new:
    x = 20
    y = 20
    w = 200
    h = 100

    - UiRect.new:
      this.centerIn root
      w = 50
      h = 50
  
  - UiText.new:
      bottom = parent.bottom
      text = "text with changed font"
      font = typeface.withSize(16)

# rect outside styler
- UiRect.new:
  right = parent.right
  bottom = parent.bottom
  w = 100
  h = 50
```


# Builtin components
see [documentation/components.md](documentation/components.md)


# Interaction with other libraries
## localize

To make sigui react to language change, create LangVar property, and bind using it
```nim
import localize
requireLocalesToBeTranslated ("ru", "")

# ...

var locale = locale("ru").property

# ...

textobj.makeLayout:
  text := locale[].tr "text to be translated"

# ...

when isMainModule:
  updateTranslations()
```
