import unittest
import sigui

type
  Tab* = ref object of Uiobj
    name*: Property[string]
    selected*: Property[bool]
    selfSelected*: Event[void]

  TabBar* = ref object of Uiobj
    tabs*: Property[seq[string]]
    selectedTab*: Property[int]


method init*(this: Tab) =
  procCall this.super.init()

  this.makeLayout:
    - MouseArea.new as mouse:
      this.fill(parent)

      on this.mouseDownAndUpInside:
        root.selfSelected.emit()

    - UiRect.new:
      this.fill(parent)

      color = binding:
        let basecolor =
          if root.selected[]: color(0.9, 0.9, 0.9)
          else: color(1, 1, 1)

        if mouse.pressed[]: basecolor.darken(0.2)
        elif mouse.hovered[]: basecolor.darken(0.1)
        else: basecolor
      
      - this.color.transition(0.2's):
        easing = outSquareEasing
    
    - UiRect.new:
      this.fillHorizontal(parent, 2)
      bottom = parent.bottom
      h = 4
      radius = 2

      color = binding:
        if root.selected[]: color(0.3, 0.3, 0.8)
        else: color(0.4, 0.4, 0.4)
      
      - this.color.transition(0.2's):
        easing = outSquareEasing

    - UiText.new:
      centerX = parent.center
      centerY = parent.center - 1
      
      color = binding:
        if root.selected[]: color(0, 0, 0)
        else: color(0.5, 0.5, 0.5)

      - this.color.transition(0.2's):
        easing = outSquareEasing

      text = binding: root.name[]
      
    


method init*(this: TabBar) =
  procCall this.super.init()

  this.makeLayout:
    var tabWidth: Property[float32]
    this.bindingValue tabWidth[]: this.w[] / this.tabs[].len.float32

    --- Uiobj.new:
      <--- Uiobj.new: root.tabs[]
      
      this.fill(parent)

      for i, name in root.tabs[]:
        - Tab.new as tab:
          this.fillVertical(parent)
          w = binding: tabWidth[]
          x = binding: i.float32 * tabWidth[]

          name = name
          selected = binding: i == root.selectedTab[]

          on this.selfSelected:
            root.selectedTab[] = i



test "tab bar":
  const typefaceFile = staticRead "../tests/Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  let lightTheme = makeStyle:
    UiText:
      font = typeface.withSize(16)
      color = "000000"


  let window = newUiWindow(size = ivec2(1280, 720), title = "tab bar")

  window.makeLayout:
    this.clearColor = color(1, 1, 1)

    - Styler.new:
      this.fill(parent)
      style = lightTheme

      - TabBar.new as tabbar:
        this.fillHorizontal(parent)
        h = 40
        
        tabs = @[
          "Overview", "Settings", "Debug", "Help",
        ]

        selectedTab = 0

      --- Uiobj.new:
        <--- Uiobj.new: tabbar.selectedTab[]

        this.fill(parent)
        top = tabbar.bottom

        case tabbar.selectedTab[]:
        of 0:
          - UiText.new:
            this.centerIn(parent)
            text = "Overview"
              
        of 1:
          - UiText.new:
            this.centerIn(parent)
            text = "Settings"
        
        of 2:
          - UiText.new:
            this.centerIn(parent)
            text = "Debug"
        
        of 3:
          - UiText.new:
            this.centerIn(parent)
            text = "Help"
        
        else:
          discard


  run window


