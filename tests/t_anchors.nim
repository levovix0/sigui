import unittest, sugar
import siwin
import sigui

test "anchors":
  let window = newOpenglWindow(size = ivec2(1280, 720), title = "anchors").newUiWindow
  
  const typefaceFile = staticRead "Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  window.makeLayout:
    this.clearColor = "fff"
    const margin = 40
    
    var w = 0'f32.property
    var h = 0'f32.property
    this.bindingValue w[]: (this.w[] - margin * 4) / 3
    this.bindingValue h[]: (this.h[] - margin * 4) / 3

    proc text(s: string): UiText =
      result = UiText()
      init result
      result.text[] = s
      result.font[] = typeface.withSize(16)

    - UiRectBorder() as rect_tl:
      this.left = parent.left + margin
      this.top = parent.top + margin

      - text "right = parent.right":
        this.right = parent.right
    
    - UiRectBorder() as rect_tm:
      this.left = rect_tl.right + margin
      this.top = parent.top + margin

      - text "top = parent.bottom":
        this.top = parent.bottom
    
    - UiRectBorder() as rect_tr:
      this.right = parent.right - margin
      this.top = parent.top + margin

      - text "bottom = parent.top":
        this.bottom = parent.top

    - UiRectBorder() as rect_ml:
      this.left = parent.left + margin
      this.top = rect_tl.bottom + margin

      - text "left = parent.left\nright = parent.right\n(fillHorizontal parent)":
        # this.hAlign[] = CenterAlign
        this.left = parent.left
        this.right = parent.right
    
    - UiRectBorder() as rect_mm:
      this.left = rect_ml.right + margin
      this.top = rect_tl.bottom + margin

      - text "centerIn parent":
        this.centerIn parent
    
    - UiRectBorder() as rect_mr:
      this.right = parent.right - margin
      this.top = rect_tl.bottom + margin

      - text "centerY = parent.center":
        this.centerY = parent.center
    
    - UiRectBorder() as rect_bl:
      this.left = parent.left + margin
      this.bottom = parent.bottom - margin

      - text "centerY = parent.top\nright = parent.right":
        # this.hAlign[] = CenterAlign
        this.centerY = parent.top
        this.right = parent.right
    
    - UiRectBorder() as rect_bm:
      this.left = rect_bl.right + margin
      this.bottom = parent.bottom - margin

      - text "bottom = parent.bottom - 10":
        this.bottom = parent.bottom - 10
    
    - UiRectBorder() as rect_br:
      this.right = parent.right - margin
      this.bottom = parent.bottom - margin

      - text "left = parent.left + 10":
        this.left = parent.left + 10
    
    for this in [rect_tl, rect_tm, rect_tr, rect_ml, rect_mm, rect_mr, rect_bl, rect_bm, rect_br]:
      capture this:
        this.binding w: w[]
        this.binding h: h[]
        this.borderWidth[] = 2
        this.color[] = "333"


  run window.siwinWindow
