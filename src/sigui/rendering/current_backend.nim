
const sigui_drawing_backend* {.strdefine: "sigui.drawing_backend".}: string = "rice"

when sigui_drawing_backend == "rice":
  import ./rice_backend
  export rice_backend

# elif sigui_drawing_backend == "figdraw":
#   import ./figdraw_backend
#   export figdraw_backend

