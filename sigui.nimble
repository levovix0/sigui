version       = "0.2.1"
author        = "levovix0"
description   = "Flexieble gui framework"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.0.8"
requires "fusion"  # to write macros using pattern matching
requires "siwin >= 0.9"  # to make window
# optional: requires "imageman"  # to decode png
requires "bumpy"  # for rects
requires "opengl"  # for graphics
requires "shady"  # for writing shaders in Nim istead of GLSL
  # imples: requires "pixie"  # for complex paths (like text and svg) rendering

task docs, "Write the package docs":
  exec "nim doc --project --index:on --git.url:git@github.com:levovix0/sigui.git --git.commit:master -o:docs/apidocs src/sigui.nim"
