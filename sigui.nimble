version       = "0.1.0"
author        = "levovix0"
description   = "Flexieble gui framework"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.0.0"
requires "fusion"  # to write macros using pattern matching
requires "siwin >= 0.8.4.5"  # to make window
requires "imageman"  # to decode png  #? just use pixie instead?
requires "bumpy"  # for rects
requires "opengl"  # for graphics
requires "shady"  # for writing shaders in Nim istead of GLSL
  # note: shady imples pixie  # for complex paths (like text and svg) rendering

task docs, "Write the package docs":
  exec "nim doc --project --index:on --git.url:git@github.com:levovix0/sigui.git --git.commit:master -o:docs/apidocs src/sigui.nim"
