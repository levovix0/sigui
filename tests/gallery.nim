## Component gallery: recreates a UIKit-style controls gallery using sigui.
##
## Run with no arguments to open an interactive window:
##   nim r gallery.nim
## Run with --headless to render the gallery without showing a window
## (tests the headless rendering tools from sigui/testutils):
##   nim r gallery.nim -- --headless <out.png> [--repr]
##
## `buildGallery` fills a `GalleryRefs` object with references to the components,
## so t_headless.nim can drive and inspect them.

import pkg/chroma
import sigui
import components

const typefaceFile* = staticRead "Roboto-Regular.ttf"

type
  Gallery* = ref object of Uiobj
    button*: Button
    disabledButton*: Button
    switch*: Switch
    slider*: Slider
    progress*: ProgressView
    spinner*: ActivityIndicatorView
    textField*: TextField
    searchBar*: SearchBar
    segmented*: SegmentedControl
    stepper*: Stepper
    pageControl*: PageControl
    checkBox*: CheckBox
    tableView*: TableView
    navBar*: NavigationBar
    tabBar*: TabBar

    buttonTaps*: int
    backTaps*: int
    sliderEdits*: int
    switchChanges*: int
    stepperChanges*: int


method init*(this: Gallery) =
  procCall this.super.init()
  
  let typeface = parseTtf(typefaceFile)
  let
    fontTitle = typeface.withSize(20)
    fontSection = typeface.withSize(12)
    fontBody = typeface.withSize(15)
    fontSmall = typeface.withSize(13)

  proc title(parent: Uiobj, text: string) =
    parent.makeLayout:
      - Label.new:
        text = text
        font = fontSection
        textColor = color_label_secondary

  this.makeLayout:
    this.fill(parent)
    this.parentUiWindow.clearColor = color(1, 1, 1)

    - Layout.new:
      this.col(gap = 8)
      this.fill(parent, 16, 12)

      - Label.new:
        text = "Gallery"
        font = fontTitle

      - Layout.new:
        this.row(gap = 24)
        w = binding: parent.w[]

        #----- left column -----#

        - Layout.new:
          this.col(gap = 6)
          w := parent.w[] / 2 - 12

          this.title("Button")
          - Layout.new:
            this.row(gap = 8)
            w := parent.w[]

            - Button.new as root.button:
              w = 140; h = 30
              title = "Button"
              this.setFont(fontBody)
              on this.tapped:
                inc root.buttonTaps

            - Button.new as root.disabledButton:
              w = 140; h = 30
              title = "Disabled"
              enabled = false
              this.setFont(fontBody)

          this.title("Switch")
          - Switch.new as root.switch:
            w = 51; h = 31
            on this.changed:
              inc root.switchChanges

          this.title("Slider")
          - Slider.new as root.slider:
            w = 220; h = 31
            value = 0.3
            on this.valueEdited:
              inc root.sliderEdits

          this.title("Progress View")
          - ProgressView.new as root.progress:
            w = 220; h = 4
            progress = 0.4

          this.title("Activity Indicator")
          - ActivityIndicatorView.new as root.spinner:
            w = 32; h = 32

          this.title("Text Field")
          - TextField.new as root.textField:
            w = 220; h = 28
            placeholder = "Placeholder"
            this.setFont(fontBody)

          this.title("Search Bar")
          - SearchBar.new as root.searchBar:
            w = 220; h = 36
            this.setFont(fontBody)

          this.title("Segmented Control")
          - SegmentedControl.new as root.segmented:
            w = 220; h = 28
            segments = @["first", "second", "third"]
            selectedIndex = 0
            font = fontSmall

        #----- right column -----#

        - Layout.new:
          this.col(gap = 6)
          w := parent.w[] / 2 - 12

          this.title("Stepper")
          - Stepper.new as root.stepper:
            w = 94; h = 29
            font = fontBody
            on this.valueChanged:
              inc root.stepperChanges

          this.title("Page Control")
          - PageControl.new as root.pageControl:
            w = 100; h = 12
            numberOfPages = 5
            currentPage = 1

          this.title("Check Box")
          - CheckBox.new as root.checkBox:
            title = "checked"
            isChecked = true
            this.setFont(fontBody)

          this.title("Table View")
          - TableView.new as root.tableView:
            w = 220; h = 132
            items = @["alpha", "beta", "gamma"]
            this.setFont(fontBody)

          this.title("Navigation Bar")
          - NavigationBar.new as root.navBar:
            w = 220; h = 44
            title = "Title"
            this.setFont(fontBody)
            on this.backTapped:
              inc root.backTaps

          this.title("Tab Bar")
          - TabBar.new as root.tabBar:
            w = 220; h = 49
            tabs = @["one", "two", "three"]
            selectedIndex = 0
            font = fontSmall


when isMainModule:
  import std/os
  import sigui/testutils

  let args = commandLineParams()

  if args.len > 0 and args[0] == "--headless":
    let win = newHeadlessUiWindow(size = ivec2(560, 540))
    win.makeLayout:
      - Gallery.new
    win.settleAnimations()

    let outPath =
      if args.len > 1: args[1]
      else: "gallery.png"

    if "--repr" in args:
      echo win.uiRepr
    if "--repr" notin args or "--screenshot" in args:
      win.saveScreenshot outPath
      echo "saved to ", outPath

  else:
    let win = newUiWindow(size = ivec2(560, 540), title = "Gallery")
    win.makeLayout:
      - Gallery.new
    run win
