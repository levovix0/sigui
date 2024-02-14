import unittest
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
      initIfNeeded result
      result.text[] = s
      result.font[] = typeface.withSize(16)

    - UiRectBorder() as rect_tl:
      left = parent.left + margin
      top = parent.top + margin

      - text "right = parent.right":
        right = parent.right
    
    - UiRectBorder() as rect_tm:
      left = rect_tl.right + margin
      top = parent.top + margin

      - text "top = parent.bottom":
        top = parent.bottom
    
    - UiRectBorder() as rect_tr:
      right = parent.right - margin
      top = parent.top + margin

      - text "bottom = parent.top":
        bottom = parent.top

    - UiRectBorder() as rect_ml:
      left = parent.left + margin
      top = rect_tl.bottom + margin

      - text "left = parent.left\nright = parent.right\n(fillHorizontal parent)":
        # hAlign = CenterAlign
        left = parent.left
        right = parent.right
    
    - UiRectBorder() as rect_mm:
      left = rect_ml.right + margin
      top = rect_tl.bottom + margin

      - text "centerIn parent":
        this.centerIn parent
    
    - UiRectBorder() as rect_mr:
      right = parent.right - margin
      top = rect_tl.bottom + margin

      - text "centerY = parent.center":
        centerY = parent.center
    
    - UiRectBorder() as rect_bl:
      left = parent.left + margin
      bottom = parent.bottom - margin

      - text "centerY = parent.top\nright = parent.right":
        # this.hAlign[] = CenterAlign
        centerY = parent.top
        right = parent.right
    
    - UiRectBorder() as rect_bm:
      left = rect_bl.right + margin
      bottom = parent.bottom - margin

      - text "bottom = parent.bottom - 10":
        bottom = parent.bottom - 10
    
    - UiRectBorder() as rect_br:
      right = parent.right - margin
      bottom = parent.bottom - margin

      - text "left = parent.left + 10":
        left = parent.left + 10
    
    for this in [rect_tl, rect_tm, rect_tr, rect_ml, rect_mm, rect_mr, rect_bl, rect_bm, rect_br]:
      w := w[]
      h := h[]
      borderWidth = 2
      color = "333"


  run window.siwinWindow
