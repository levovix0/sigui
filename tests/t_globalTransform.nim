import std/unittest
import sigui/[uibase, uiobjMacros]


proc `~==`(a, b: float): bool = almostEqual(a, b)


test "globalTransform: anchor sets global coordinates":
  let root = new UiRoot
  var container: Uiobj
  var gtObj: Uiobj

  root.makeLayout:
    w = 1000
    h = 800

    - Uiobj.new as (container):
      left = parent.left + 10
      right = parent.right - 10
      top = parent.top + 10
      bottom = parent.bottom - 10

    - Uiobj.new as (gtObj):
      globalTransform = true
      left = container.left + 50
      right = container.right - 50
      top = container.top + 30
      bottom = container.bottom - 30

  check container.x[] ~== 10
  check container.globalX[] ~== 10

  check gtObj.globalX[] ~== 60.0
  check gtObj.globalY[] ~== 40.0
  check gtObj.x[] ~== 60.0
  check gtObj.y[] ~== 40.0
  check gtObj.w[] ~== 880.0
  check gtObj.h[] ~== 720.0


test "globalTransform: posToGlobal uses actual global position":
  let root = new UiRoot
  var gtObj: Uiobj
  var innerObj: Uiobj

  root.makeLayout:
    w = 1000
    h = 800

    - Uiobj.new:
      left = parent.left + 10
      right = parent.right - 10
      top = parent.top + 10
      bottom = parent.bottom - 10

      - Uiobj.new as (gtObj):
        globalTransform = true
        left = parent.left + 50
        top = parent.top + 30
        w = 200
        h = 100

        - Uiobj.new as (innerObj):
          this.fill(parent)

  check gtObj.globalX[] ~== 60.0
  check gtObj.globalY[] ~== 40.0

  check innerObj.x[] ~== 0.0
  check innerObj.globalX[] ~== 60.0

  let drawPos = vec2(innerObj.x[], innerObj.y[]).posToGlobal(innerObj.parent)
  check drawPos.x ~== innerObj.globalX[]
  check drawPos.y ~== innerObj.globalY[]


test "globalTransform: posToLocal is inverse of posToGlobal":
  let root = new UiRoot
  var gtObj: Uiobj

  root.makeLayout:
    w = 1000
    h = 800
    
    - Uiobj.new:
      left = parent.left + 10
      top = parent.top + 10
      w = 500
      h = 400

      - Uiobj.new as (gtObj):
        globalTransform = true
        left = parent.left + 50
        top = parent.top + 30
        w = 200
        h = 100

  let globalPos = vec2(200'f32, 150'f32)
  let localPos = globalPos.posToLocal(gtObj)
  let backToGlobal = localPos.posToGlobal(gtObj)
  check backToGlobal.x ~== globalPos.x
  check backToGlobal.y ~== globalPos.y


test "globalTransform: position stays correct when parent changes size":
  let root = new UiRoot
  var gtObj: Uiobj

  root.makeLayout:
    w = 1000
    h = 800

    - Uiobj.new:
      left = parent.left + 10
      right = parent.right - 10
      top = parent.top + 10
      bottom = parent.bottom - 10

      - Uiobj.new as (gtObj):
        globalTransform = true
        left = parent.left + 50
        right = parent.right - 50
        top = parent.top + 30
        bottom = parent.bottom - 30
  
  check gtObj.w[] ~== 880.0
  check gtObj.globalX[] ~== 60.0

  root.w[] = 1200
  check gtObj.w[] ~== 1080.0
  check gtObj.globalX[] ~== 60.0
