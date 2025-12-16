note: all example code here assumes it is written inside makeLayout, to construct a full example code file, wrap it in window:
```nim
import sigui

let win = newUiWindow()

win.makeLayout:
  ## example code here

run win
```
window by default has no title, size (1280, 720), and opaque black background (clear) color


# Uiobj
inherits `RootObj`, import it from `sigui/uiobj` or `sigui/uibase`

Base type for all components. Displays nothing. Can be used as container for anchor-based positioning.

Properties:
- `x, y, w, h: Property[float32]` - position of rect of the object
- `visibility: Property[Visibility]` - is component `visible`, `hidden` (does not draw anything), `hiddenTree` (does not draw, including it's children) or `collapsed` (does not draw, does not count in layouts, behaves like zero-sized component in anchoring)
- `globalTransform: Property[bool]` - if true, x and y of this object is relative to UiRoot's top-left courner, if false, relative to parent's top-left courner
- `globalX, globalY: Property[float32]` - position, relative to UiRoot (the window)

Example:
```nim
- Uiobj.new:
  x = 100; y = 100; w = 100; h = 100

  - UiRect.new:
    this.fill(parent)
    
    color = "#ff0000".color

  - UiRect.new:
    w = 30
    centerX = parent.center
    top = parent.top
    bottom = parent.bottom
    
    color = "#00ff00".color
```


# UiRect
inherits `Uiobj`, import it from `sigui/uibase`

Displays a flat-colored rectangle. Can have rounded couners.

Properties:
- `color: Property[Col]` - fill color of this rect
- `radius: Property[float32]` - rounding radius for all four courners
- DEPRECATED `angle: Property[float32]` - rotation angle, with origin at top-left courner

Example:
```nim
- UiRect.new:
  this.centerIn(parent)
  w = 200
  h = 100
  
  radius = 10
  color = "#ff0000".color
```


# UiImage
inherits `Uiobj`, import it from `sigui/uibase`

Displays a raster image. Can have rounded couners.
Can be used for icons with colorOverlay=true (but it's preferable to use UiSvgImage instead).

To load an image into UiImage use `image=(UiImage, pixie.Image)`. UiImage without an image displays nothing.
when image is loaded, sets w and h equal to source images width and height (but only if current w and h was (0, 0))
Supports image loading from [pixie](https://github.com/treeform/pixie) and [imageman](https://github.com/SolitudeSF/imageman)

Properties:
- `radius: Property[float32]` - rounding radius for all four courners
- `blend: Property[bool]` - if false, image will be drawn without color mixin with current background
- `imageWh: Property[IVec2]` - size of source image in pixels
- `color: Property[Col]` - color to multiply with each pixel of image, or color of every non-transparent pixel of the image if colorOverlay is true
- `colorOverlay: Property[bool]` - if true, image will have flat color, with image alpha working like a mask (useful for icons)
- DEPRECATED `angle: Property[float32]` - rotation angle, with origin at top-left courner

Example:
```nim
- UiImage.new:
  this.centerIn(parent)
  
  radius = 10
  this.image = readImage("image.png")
```


# UiSvgImage
inherits `Uiobj`, import it from `sigui/uibase`

Displays a vector (svg) image by turning it into a raster image via [pixie](https://github.com/treeform/pixie). Can have rounded couners.
Always behaves like UiImage with colorOverlay=true. Should be used for icons.

To load an image into UiSvgImage set the `image` property of this object to contents of svg image file. ~~And pray that pixie will be able to parse it.~~
If w or h of this component is changed, image will be re-rendered to pixel-perfectly match target resolution.

Properties:
- `radius: Property[float32]` - rounding radius for all four courners
- `blend: Property[bool]` - if false, image will be drawn without color mixin with current background
- `image: Property[string]` - source svg image text
- `imageWh: Property[IVec2]` - size of source image in pixels (if specified in svg file)
- `color: Property[Col]` - color of every non-transparent pixel of the image
- DEPRECATED `angle: Property[float32]` - rotation angle, with origin at top-left courner

Example:
```nim
- UiSvgImage.new:
  this.centerIn(parent)
  
  image = readFile("icon.svg")
  color = "#ffffff".color
```


# UiRectBorder
inherits `UiRect`, import it from `sigui/uibase`

Displays a thin rect border. Can have rounded courners. Can be a dotted line (`-- -- --`, but not `- . -` or `-- ---- --`).

Properties:
- `borderWidth: Property[float32]` - width of the border line, extends inside component's rect
- `tiled: Property[bool]` - is this a dotted line (`-- -- --`)
- `tileSize: Property[Vec2]` - width of visible line segment of a dotted line
- `tileSecondSize: Property[Vec2]` - width of invisible line segment of a dotted line
- `secondColor: Property[Col]` - color of "invisible" line segment of a dotted line, transparent by default

Properties from UiRect:
- `color: Property[Col]` - color of the border line
- `radius: Property[float32]` - rounding radius for all four courners
- DEPRECATED `angle: Property[float32]` - rotation angle, with origin at top-left courner

Example:
```nim
- UiRectBorder.new:
  this.centerIn(parent)
  w = 200
  h = 100
  
  radius = 10
  color = "#ffffff".color

- UiRectBorder.new:
  this.centerIn(parent)
  w = 180
  h = 80
  
  radius = 10
  borderWidth = 2
  color = "#ffffff".color
  
  tiled = true
  tileSize = vec2(4, 4)
  tileSecondSize = vec2(2, 2)
```


# RectShadow
inherits `UiRect`, import it from `sigui/uibase`

Displays a shadow of a rect (rect with gradient of the sides).

Shadow does not exceed the size of this object, so usualy it's filled relative to parent with negative margin.
If blurRadius is dynamic, `binding: this.fill(parent, -this.blurRadius[])` can be used.
(todo: make blur outside of component's rect, this is the most used case, setting margin equal to negative blurRadius is inconvinient)

Properties:
- `blurRadius: Property[float32]` - length of the gradient between (transparent) side and (flat-colored) inside

Properties from UiRect:
- `color: Property[Col]` - color of the shadow. Use lower color alpha for lower shadow intensity
- `radius: Property[float32]` - rounding radius for all four courners
- DEPRECATED `angle: Property[float32]` - rotation angle, with origin at top-left courner

Example:
```nim
- UiRect.new:
  this.centerIn(parent)
  w = 100
  h = 100
  
  radius = 10
  color = "#ff0000".color

  - UiRectShadow.new:
    this.fill(parent, -10)
    blurRadius = 10
    this.drawLayer = before parent
    
    radius = 10
    color = "#00ff00".color
```


# ClipRect
inherits `Uiobj`, import it from `sigui/uibase`

Displays content clipping it to the box of this component.

Properties:
- `radius: Property[float32]` - rounding radius for all four courners
- `color: Property[Col]` - color to multiply with each pixel of the content of this component
- DEPRECATED `angle: Property[float32]` - rotation angle, with origin at top-left courner


# UiText
inherits `Uiobj`, import it from `sigui/uibase`

Displays text, rendering each letter to a raster image buffer and drawing it in boxes of arrangement, made by [pixie](https://github.com/treeform/pixie).

Properties:
- `text: Property[string]` - the text to display
- `font: Property[Font]` - font (typeface and fontSize) of text to display. Must be provided or text won't display
- `bounds: Property[Vec2]` - bounds of arrangement generated by pixie, can be used to display multiline text. If zero, text is displayed in single line
- `hAlign: Property[HorizontalAlignment]` - horizontal alignment of arrangement generated by pixie, used in multiline text
- `vAlign: Property[VerticalAlignment]` - vertical alignment of arrangement generated by pixie, used in multiline text
- `color: Property[Col]` - color of the text
- `arrangement: Property[Arrangement]` - arrangement, generated by pixie (automatically, if text and font are set)
- DEPRECATED `roundPositionOnDraw: Property[bool]` - if false, at draw time, text is rendered at float coordinates

Example:
```nim
let typeface = "font.ttf".staticRead.static.parseTtf

- UiText.new:
  this.centerIn(parent)
  text = "Hello, world!"
  font = typeface.withSize(14)
  color = "#ffffff".color
```


## Text Area
inherits `Uiobj`, import it from `sigui/textArea`

https://github.com/levovix0/sigui/assets/53170138/56007317-7558-459d-bf79-ff9b44b7ac6b

Area that allows user to view, select and edit text. Text is cropped to the box of this component.

Set `allowedInteractions = this.allowedInteractions[] - {textInput}` if you need only text selection from this component.

Events:
- `textEdited: Event[void]` - text was edited by user
- `keyDown: Event[KeyEvent]` - key was pressed with this component beeng active (focused)

Properties:
- `active: Property[bool]` - is this component focused
- `text: Property[string]` - current text
- `cursorPos: CustomProperty[int]` - position of text cursor (counting in std/unicode Rune's)
- `blinking: Blinking` - text cursor blinking settings
- `selectionStart, selectionEnd*: CustomProperty[int]` - start and end of selection (counting in std/unicode Rune's)
- `followCursorOffset: Property[float32]` - minimal length in scaled pixels when text cursor is considered out of bounds of this area, when text should be visially moved to fit text cursor
- `cursorX: Property[float32]` - position of text cursor in scaled pixels, can be animated
- `offset: Property[float32]` - offset of text in scaled pixels (when it is moved outside of bounds), can be animated
- `selectionStartX, selectionEndX*: Property[float32]` - position of start and end of selection in scaled pixels, can be animated

Fields:
- `allowedInteractions: set[TextAreaInteraction]` - is textInput enabled, what mouse interactions are handled and what keybindings are handled
- `undoBufferLimit: int` - max entry count in undoBuffer (for ctrl-Z)

Inner components:
- `cursorObj: ChangableChild[Uiobj]` - object used as text cursor, UiRect by default
- `selectionObj: ChangableChild[Uiobj]` - object used as selection background, UiRect by default
- `textObj {.cursor.}: UiText` - object used to display text
- `mouseArea {.cursor.}: MouseArea` - object used for mouse interactions (can be bigger than textArea)
- `textArea {.cursor.}: ClipRect` - the actual box for the text inside this object

Example:
```nim
let typeface = "font.ttf".staticRead.static.parseTtf

- TextArea.new:
  this.centerIn(parent)
  w = 100
  h = 24

  text = "start text"
  + this.textObj:
    font = typeface.withSize(24)
    color = "#ffffff".color

  # note: create your own UiText to make tip/hint
```


# Other components
Undocumented yet.

- MouseArea
- UiPath
- Styler
- ScrollArea
- Layout
- GlobalKeybinding
- UiRoot
- UiWindow
- HostUiRoot
- PluginUiRoot


# Components in toscel (component library for sigui)
Undocumented yet.

- Label
- Button
- ThemedUiText (UiText with predefined font and color)
- LineEdit
- ~~CheckBox~~ wip
- ~~CheckableIcon~~ wip
- ~~Themer~~ wip
