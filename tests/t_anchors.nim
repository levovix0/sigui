import unittest
import sigui

test "anchors":
  let window = newUiWindow(size = ivec2(1280, 720), title = "anchors")
  
  const typefaceFile = staticRead "Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  window.makeLayout:
    this.clearColor = "fff"
    const margin = 40
    
    var w = 0'f32.property
    var h = 0'f32.property
    this.bindingValue w[]: (this.w[] - margin * 4) / 3
    this.bindingValue h[]: (this.h[] - margin * 4) / 3

    - Uiobj.new as background

    proc text(container: Uiobj, s: string): UiText =
      result.makeLayoutInside(container, UiText.new):
        text = s
        font = typeface.withSize(16)
        
        - UiRect.new:
          this.fill parent
          layer = after background
          color = "c0c0c0"

    - UiRectBorder.new as rect_tl:
      left = parent.left + margin
      top = parent.top + margin

      + this.text "right = parent.right":
        right = parent.right
    
    - UiRectBorder.new as rect_tm:
      left = rect_tl.right + margin
      top = parent.top + margin

      + this.text "top = parent.bottom":
        top = parent.bottom
    
    - UiRectBorder.new as rect_tr:
      right = parent.right - margin
      top = parent.top + margin

      + this.text "bottom = parent.top":
        bottom = parent.top

    - UiRectBorder.new as rect_ml:
      left = parent.left + margin
      top = rect_tl.bottom + margin

      + this.text "left = parent.left\nright = parent.right\n(fillHorizontal parent)\nmargin = 10":
        # hAlign = CenterAlign
        left = parent.left
        right = parent.right
        this.margin = 10
    
    - UiRectBorder.new as rect_mm:
      left = rect_ml.right + margin
      top = rect_tl.bottom + margin

      + this.text "centerIn parent":
        this.centerIn parent
    
    - UiRectBorder.new as rect_mr:
      right = parent.right - margin
      top = rect_tl.bottom + margin

      + this.text "centerY = parent.center":
        centerY = parent.center
    
    - UiRectBorder.new as rect_bl:
      left = parent.left + margin
      bottom = parent.bottom - margin

      + this.text "centerY = parent.top\nright = parent.right":
        # this.hAlign[] = CenterAlign
        centerY = parent.top
        right = parent.right
    
    - UiRectBorder.new as rect_bm:
      left = rect_bl.right + margin
      bottom = parent.bottom - margin

      + this.text "bottom = parent.bottom - 10":
        bottom = parent.bottom - 10
    
    - UiRectBorder.new as rect_br:
      right = parent.right - margin
      bottom = parent.bottom - margin

      + this.text "left = parent.left + 10":
        left = parent.left + 10
    
    for this in [rect_tl, rect_tm, rect_tr, rect_ml, rect_mm, rect_mr, rect_bl, rect_bm, rect_br]:
      w := w[]
      h := h[]
      borderWidth = 2
      color = "333"


  run window
