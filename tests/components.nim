## An example of component library, recreating (simplified) Apple UIKit controls.
## Used by gallery.nim and t_headless.nim.
##
## note: Here all component types are declared near their respective init methods.
## This is made for easier component example lookup/search because this is an example component library.
## In real application it is recommended to place all types at the top of the module.

import std/[math]
import pkg/[chroma]
import sigui

const PI32* = 3.14159265'f32

#----- iOS-like color palette -----

const
  color_blue* = "007AFF".color
  color_green* = "34C759".color
  color_red* = "FF3B30".color
  color_orange* = "FF9500".color
  color_gray* = "8E8E93".color
  color_gray2* = "AEAEB2".color
  color_gray4* = "D1D1D6".color
  color_gray5* = "E5E5EA".color
  color_gray6* = "F2F2F7".color
  color_label* = "000000".color
  color_label_secondary* = color("3C3C43".color.r, "3C3C43".color.g, "3C3C43".color.b, 0.6)

proc withAlpha*(c: Color, a: float32): Color =
  color(c.r, c.g, c.b, a)


#----- Button -----

type
  Button* = ref object of Uiobj
    title*: Property[string] = "".property
      ## text displayed on the button
    enabled*: Property[bool] = true.property
    tintColor*: Property[Color] = color_blue.property
    tapped*: Event[void]
      ## emits when the button is clicked while enabled

    label: UiText

registerComponent Button


method init*(this: Button) =
  procCall this.super.init()

  this.makeLayout:
    w = 120
    h = 34

    - UiRect.new:
      this.fill parent
      radius = binding: min(this.w[], this.h[]) / 2
      color = binding:
        if not root.enabled[]: color_gray4
        elif mouse.pressed[]: root.tintColor[].darken(0.2)
        elif mouse.hovered[]: root.tintColor[].lighten(0.15)
        else: root.tintColor[]

      - this.color.transition(initDuration(milliseconds = 100))

      - UiText.new as root.label:
        this.centerIn parent
        text = binding: root.title[]
        color = binding:
          if root.enabled[]: color(1, 1, 1)
          else: color(1, 1, 1).withAlpha(0.6)

      - MouseArea.new as mouse:
        this.fill parent
        on this.clicked:
          if root.enabled[]:
            root.tapped.emit()


proc setFont*(this: Button, font: Font) =
  this.label.font[] = font


#----- Switch -----

type
  Switch* = ref object of Uiobj
    isOn*: Property[bool]
    tintColor*: Property[Color] = color_green.property
    changed*: Event[bool]
      ## emits the new isOn value when the switch is toggled

registerComponent Switch


method init*(this: Switch) =
  procCall this.super.init()

  this.makeLayout:
    w = 51
    h = 31

    - UiRect.new as track:
      this.fill parent
      radius = binding: min(this.w[], this.h[]) / 2
      color = binding:
        if root.isOn[]: root.tintColor[]
        elif mouse.hovered[]: color_gray.lighten(0.2)
        else: color_gray

      - this.color.transition(initDuration(milliseconds = 150))

      - UiRect.new as knob:
        centerY = parent.center
        w = 27
        h = 27
        radius = 13.5
        color = color(1, 1, 1)
        x = binding:
          if root.isOn[]: parent.w[] - this.w[] - 2
          else: 2'f32

        - this.x.transition(initDuration(milliseconds = 150)):
          easing = outCubicEasing

      - MouseArea.new as mouse:
        this.fill parent
        on this.clicked:
          root.isOn[] = not root.isOn[]
          root.changed.emit(root.isOn[])


#----- Slider -----

type
  Slider* = ref object of Uiobj
    value*: Property[float32] = 0.5'f32.property
      ## normalized value, 0..1
    valueEdited*: Event[float32]
      ## emits on every value change made by the user
    tintColor*: Property[Color] = color_blue.property

registerComponent Slider


method init*(this: Slider) =
  procCall this.super.init()

  this.makeLayout:
    w = 200
    h = 31

    proc updateFromMouse() =
      let t = clamp(mouse.mouseX[] / max(1'f32, this.w[]), 0'f32, 1'f32)
      if this.value[] != t:
        this.value[] = t
        this.valueEdited.emit(t)

    - UiRect.new as trackLeft:
      centerY = parent.center
      h = 4
      radius = 2
      color = binding: root.tintColor[]
      w = binding: knob.x[] + knob.w[] / 2

    - UiRect.new as trackRight:
      centerY = parent.center
      h = 4
      radius = 2
      color = color_gray4
      x = binding: knob.x[] + knob.w[] / 2
      w = binding: parent.w[] - this.x[]

    - UiRect.new as knob:
      centerY = parent.center
      w = 27
      h = 27
      radius = 13.5
      color = binding:
        if mouse.pressed[]: color_gray2
        else: color(1, 1, 1)
      x = binding: (parent.w[] - this.w[]) * root.value[]

      - UiRectBorder.new:
        this.fill parent
        radius = 13.5
        borderWidth = 0.5
        color = color_gray2

    - MouseArea.new as mouse:
      this.fill parent
      on this.pressed[] == true: updateFromMouse()
      on this.moved:
        if this.pressed[]: updateFromMouse()
      on this.clicked: updateFromMouse()


#----- ProgressView -----

type
  ProgressView* = ref object of Uiobj
    progress*: Property[float32]
      ## 0..1
    progressTintColor*: Property[Color] = color_blue.property
    trackTintColor*: Property[Color] = color_gray5.property

registerComponent ProgressView


method init*(this: ProgressView) =
  procCall this.super.init()

  this.makeLayout:
    h = 4

    - UiRect.new as track:
      centerY = parent.center
      w = binding: parent.w[]
      h = 4
      radius = 2
      color = binding: root.trackTintColor[]

    - UiRect.new as fill:
      centerY = parent.center
      h = 4
      radius = 2
      color = binding: root.progressTintColor[]
      w = binding: parent.w[] * clamp(root.progress[], 0'f32, 1'f32)


#----- ActivityIndicator -----

type
  ActivityIndicatorView* = ref object of Uiobj
    isAnimating*: Property[bool] = true.property
      ## if false, all spokes are dimmed
    tintColor*: Property[Color] = color_gray.property

    time: Property[float32] = 0'f32.property
      ## advanced automatically by ticks, used to rotate the spokes

registerComponent ActivityIndicatorView


method init*(this: ActivityIndicatorView) =
  procCall this.super.init()

  this.makeLayout:
    w = 32
    h = 32

    for i in 0 ..< 8:
      - UiRect.new:
        w = 3.5
        h = 3.5
        radius = 1.75
        x = binding:
          parent.w[] / 2 + cos((i.float32 / 8 * 2 * PI32) - root.time[] * 2 * PI32) * 12 - this.w[] / 2
        y = binding:
          parent.h[] / 2 + sin((i.float32 / 8 * 2 * PI32) - root.time[] * 2 * PI32) * 12 - this.h[] / 2
        color = binding:
          let spokePhase = (root.time[] + 1 - i.float32 / 8) mod 1
          let intensity = if root.isAnimating[]: 0.25 + (1 - spokePhase) * 0.75 else: 0.25
          root.tintColor[].withAlpha(intensity)

    this.root.onTick.connectTo this, e:
      if root.isAnimating[]:
        root.time[] = (root.time[] + e.deltaTime.inMicroseconds.float32 / 1_000_000) mod 1


#----- TextField -----

type
  TextField* = ref object of Uiobj
    placeholder*: Property[string]
    showsBorder*: Property[bool] = true.property
    borderHighlighted*: Property[bool] = false.property
      ## if true, the border is highlighted (like when the field is focused)
    textArea*: TextArea
      ## the inner text area, public for tests
    placeholderText: UiText

registerComponent TextField


method init*(this: TextField) =
  procCall this.super.init()

  this.makeLayout:
    w = 200
    h = 28

    - UiRect.new as background:
      this.fill parent
      radius = 5
      color = color(1, 1, 1)

      - TextArea.new as area:
        this.fill(this.parent, 8, 3)

        root.textArea = this

      - UiText.new as placeholderText:
        centerY = parent.center
        left = parent.left + 9
        text = binding: root.placeholder[]
        color = color_gray2
        visibility = binding:
          if root.textArea.text[].len == 0: Visibility.visible
          else: Visibility.collapsed

        root.placeholderText = this

    - UiRectBorder.new as border:
      this.fill parent
      borderWidth = 1
      radius = 5
      color = binding:
        if root.borderHighlighted[]: color_blue
        elif root.showsBorder[]: color_gray4
        else: color(0, 0, 0, 0)

  this.textArea.allowedInteractions.excl deactivatingUsingMouse


proc `text=`*(this: TextField, v: string) =
  this.textArea.text[] = v

proc text*(this: TextField): string =
  this.textArea.text[]

proc setFont*(this: TextField, font: Font) =
  this.textArea.textObj.font[] = font
  this.placeholderText.font[] = font


#----- SegmentedControl -----

type
  SegmentedControl* = ref object of Uiobj
    segments*: Property[seq[string]]
    selectedIndex*: Property[int]
    selectionChanged*: Event[int]
    font*: Property[Font]

    content: ChangableChild[Layout]

registerComponent SegmentedControl


method init*(this: SegmentedControl) =
  procCall this.super.init()

  this.makeLayout:
    w = 220
    h = 28

    - UiRect.new as background:
      this.fill parent
      radius = 7
      color = color_gray5

    this.content --- Layout.new:
      <--- {update}: root.segments[]
      this.row(gap = 2)
      this.fill(parent, 2, 2)

      for i, segmentTitle in root.segments[]:
        - MouseArea.new:
          w := (parent.w[] - 2 * 2 - (root.segments[].len - 1).float32 * 2) / root.segments[].len.float32
          h = parent.h[]

          - UiRect.new as selection:
            this.fill parent
            radius = 5
            color = color(1, 1, 1)
            visibility = binding:
              if root.selectedIndex[] == i: Visibility.visible
              else: Visibility.collapsed

          - UiText.new:
            this.centerIn parent
            text = segmentTitle
            font = binding: root.font[]
            color = binding:
              if root.selectedIndex[] == i: color_label
              else: color_label_secondary

          on this.clicked:
            if root.selectedIndex[] != i:
              root.selectedIndex[] = i
              root.selectionChanged.emit(i)


#----- Stepper -----

type
  Stepper* = ref object of Uiobj
    value*: Property[float32] = 0'f32.property
    step*: Property[float32] = 1'f32.property
    minimum*: Property[float32] = -100'f32.property
    maximum*: Property[float32] = 100'f32.property
    valueChanged*: Event[float32]
    font*: Property[Font]
    minusButton*: MouseArea
      ## the "-" button, public for tests
    plusButton*: MouseArea
      ## the "+" button, public for tests

registerComponent Stepper


method init*(this: Stepper) =
  procCall this.super.init()

  proc updateValue(delta: float32) =
    let newValue = clamp(this.value[] + delta, this.minimum[], this.maximum[])
    if newValue != this.value[]:
      this.value[] = newValue
      this.valueChanged.emit(newValue)

  this.makeLayout:
    w = 94
    h = 29

    - UiRect.new as minusBackground:
      x = 1
      y = 1
      w = 46
      h = 27
      radius = 6
      color = binding:
        if mouseMinus.hovered[]: color_gray4
        else: color_gray6

      - UiText.new:
        this.centerIn parent
        text = "-"
        font = binding: root.font[]
        color = binding:
          if root.value[] <= root.minimum[]: color_gray4
          else: color_label

      - MouseArea.new as mouseMinus:
        this.fill parent
        root.minusButton = this
        on this.clicked: updateValue(-root.step[])

    - UiRect.new as plusBackground:
      x = 47
      y = 1
      w = 46
      h = 27
      radius = 6
      color = binding:
        if mousePlus.hovered[]: color_gray4
        else: color_gray6

      - UiText.new:
        this.centerIn parent
        text = "+"
        font = binding: root.font[]
        color = binding:
          if root.value[] >= root.maximum[]: color_gray4
          else: color_label

      - MouseArea.new as mousePlus:
        this.fill parent
        root.plusButton = this
        on this.clicked: updateValue(root.step[])

    - UiRectBorder.new:
      this.fill parent
      radius = 7
      borderWidth = 1
      color = color_gray4


#----- PageControl -----

type
  PageControl* = ref object of Uiobj
    numberOfPages*: Property[int] = 3.property
    currentPage*: Property[int]
    pageChanged*: Event[int]

    dots: ChangableChild[Layout]

registerComponent PageControl


method init*(this: PageControl) =
  procCall this.super.init()

  this.makeLayout:
    w = 100
    h = 12

    this.dots --- Layout.new:
      <--- {update}: root.numberOfPages[]
      this.row(gap = 8)
      align = center
      this.fill parent

      for i in 0 ..< root.numberOfPages[]:
        - MouseArea.new:
          w = 10
          h = 10

          - UiRect.new:
            this.centerIn parent
            w = 7
            h = 7
            radius = 3.5
            color = binding:
              if root.currentPage[] == i: color_gray
              else: color_gray.withAlpha(0.3)

          on this.clicked:
            if root.currentPage[] != i:
              root.currentPage[] = i
              root.pageChanged.emit(i)


#----- CheckBox -----

type
  CheckBox* = ref object of Uiobj
    title*: Property[string]
    isChecked*: Property[bool]
    toggled*: Event[bool]
      ## emits the new isChecked value

    titleText: UiText

registerComponent CheckBox


const checkboxSvg* = """<svg width="12" height="12" viewBox="0 0 12 12">
<path d="M2 6.5 L4.8 9.2 L10 3.4" stroke="#000000" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>"""


method init*(this: CheckBox) =
  procCall this.super.init()

  this.makeLayout:
    h = 22
    w = binding: 28 + titleText.w[]

    - MouseArea.new as mouse:
      this.fill parent

      - UiRectBorder.new as box:
        left = parent.left + 2
        centerY = parent.center
        w = 18
        h = 18
        borderWidth = 1.5
        radius = 4
        color = binding:
          if root.isChecked[]: color_blue
          elif mouse.hovered[]: color_blue.lighten(0.3)
          else: color_gray2

        - UiSvgImage.new as checkmark:
          this.centerIn parent
          image = checkboxSvg
          imageWh = ivec2(12, 12)
          w = 12
          h = 12
          color = color(1, 1, 1)
          visibility = binding:
            if root.isChecked[]: Visibility.visible
            else: Visibility.collapsed

      - UiText.new as titleText:
        centerY = parent.center
        left = box.right + 8
        text = binding: root.title[]
        color = color_label

        root.titleText = this

      on this.clicked:
        root.isChecked[] = not root.isChecked[]
        root.toggled.emit(root.isChecked[])


proc setFont*(this: CheckBox, font: Font) =
  this.titleText.font[] = font


#----- TableView -----

type
  TableView* = ref object of Uiobj
    items*: Property[seq[string]]
    selectedIndex*: Property[int] = -1.property
    rowSelected*: Event[int]
      ## emits the selected row index

    rows: ChangableChild[Layout]

registerComponent TableView


method init*(this: TableView) =
  procCall this.super.init()

  this.makeLayout:
    this.rows --- Layout.new:
      <--- {update}: root.items[]
      this.col(gap = 0)
      this.fill parent

      for i, item in root.items[]:
        - MouseArea.new as rowMouse:
          w := parent.w[]
          h = 44

          - UiRect.new as selection:
            this.fill parent
            color = binding:
              if root.selectedIndex[] == i: color_gray5
              elif rowMouse.hovered[]: color_gray6
              else: color(1, 1, 1, 0)

          - UiText.new:
            centerY = parent.center
            left = parent.left + 16
            text = item
            color = color_label

          - UiRect.new as separator:
            left = parent.left + 16
            bottom = parent.bottom
            w = binding: parent.w[] - 16
            h = 0.5
            color = color_gray4
            visibility = binding:
              if i == root.items[].high: Visibility.collapsed
              else: Visibility.visible

          on this.clicked:
            root.selectedIndex[] = i
            root.rowSelected.emit(i)


proc setFont*(this: TableView, font: Font) =
  proc applyFont(obj: Uiobj) =
    if obj of UiText:
      UiText(obj).font[] = font
    for child in obj.childs:
      child.applyFont()
  for row in this.rows[].childs:
    row.applyFont()


#----- NavigationBar -----

type
  NavigationBar* = ref object of Uiobj
    title*: Property[string]
    showsBackButton*: Property[bool] = true.property
    backTapped*: Event[void]

    titleText: UiText

registerComponent NavigationBar


method init*(this: NavigationBar) =
  procCall this.super.init()

  this.makeLayout:
    h = 44

    - UiRect.new as background:
      this.fill parent
      color = color_gray6

    - UiRect.new as separator:
      bottom = parent.bottom
      w = binding: parent.w[]
      h = 0.5
      color = color_gray4

    - MouseArea.new as backButton:
      centerY = parent.center
      left = parent.left + 8
      w = 70
      h = 30
      visibility = binding:
        if root.showsBackButton[]: Visibility.visible
        else: Visibility.collapsed

      - UiText.new:
        centerY = parent.center
        left = parent.left
        text = "‹ Back"
        color = color_blue

      on this.clicked:
        root.backTapped.emit()

    - UiText.new as titleLabel:
      this.centerIn parent
      text = binding: root.title[]
      color = color_label

      root.titleText = this


proc setFont*(this: NavigationBar, font: Font) =
  this.titleText.font[] = font


#----- TabBar -----

type
  TabBar* = ref object of Uiobj
    tabs*: Property[seq[string]]
    selectedIndex*: Property[int]
    tabChanged*: Event[int]
    font*: Property[Font]

    content: ChangableChild[Layout]

registerComponent TabBar


method init*(this: TabBar) =
  procCall this.super.init()

  this.makeLayout:
    h = 49

    - UiRect.new as background:
      this.fill parent
      color = color_gray6

    - UiRect.new as separator:
      top = parent.top
      w = binding: parent.w[]
      h = 0.5
      color = color_gray4

    this.content --- Layout.new:
      <--- {update}: root.tabs[]
      this.row(gap = 0)
      this.fill(parent, 0, 0)

      for i, tabTitle in root.tabs[]:
        - MouseArea.new:
          w := (parent.w[] - (root.tabs[].len - 1).float32 * 0) / root.tabs[].len.float32
          h = parent.h[]

          - UiRect.new as tabIcon:
            centerX = parent.center
            top = parent.top + 7
            w = 22
            h = 22
            radius = 6
            color = binding:
              if root.selectedIndex[] == i: color_blue
              else: color_gray

          - UiText.new:
            centerX = parent.center
            top = parent.top + 32
            text = tabTitle
            font = binding: root.font[]
            color = binding:
              if root.selectedIndex[] == i: color_blue
              else: color_gray

          on this.clicked:
            if root.selectedIndex[] != i:
              root.selectedIndex[] = i
              root.tabChanged.emit(i)


#----- SearchBar -----

const searchSvg* = """<svg width="16" height="16" viewBox="0 0 16 16">
<circle cx="6.5" cy="6.5" r="4.5" stroke="#000000" stroke-width="1.6" fill="none"/>
<line x1="10" y1="10" x2="14" y2="14" stroke="#000000" stroke-width="1.6" stroke-linecap="round"/>
</svg>"""


type
  SearchBar* = ref object of Uiobj
    field*: TextField
      ## the inner text field, public for tests

registerComponent SearchBar


method init*(this: SearchBar) =
  procCall this.super.init()

  this.makeLayout:
    h = 36

    - UiRect.new as background:
      this.fill parent
      radius = 9
      color = color_gray5

      - UiSvgImage.new as magnifier:
        centerY = parent.center
        left = parent.left + 8
        image = searchSvg
        imageWh = ivec2(16, 16)
        w = 16
        h = 16
        color = color_gray

      - TextField.new as field:
        centerY = parent.center
        left = magnifier.right + 6
        right = parent.right - 8
        showsBorder = false

        root.field = this


proc `text=`*(this: SearchBar, v: string) =
  this.field.text = v

proc text*(this: SearchBar): string =
  this.field.text

proc setFont*(this: SearchBar, font: Font) =
  this.field.setFont(font)


#----- Label -----

type
  Label* = ref object of Uiobj
    text*: Property[string]
    textColor*: Property[Color] = color_label.property
    font*: Property[Font]

    textObj: UiText

registerComponent Label


method init*(this: Label) =
  procCall this.super.init()

  this.makeLayout:
    - UiText.new as textObj:
      text = binding: root.text[]
      color = binding: root.textColor[]
      font = binding: root.font[]

      root.textObj = this
      this.bindingValue root.w[]: this.w[]
      this.bindingValue root.h[]: this.h[]
