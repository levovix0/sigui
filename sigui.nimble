version       = "0.3.1"
author        = "levovix0"
description   = "Flexieble gui framework"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.2.12"
requires "fusion"  # to write macros using pattern matching
requires "siwin >= 1.1.2"  # to make window

requires "bumpy"  # for rects
requires "rice == 0.1.8"  # for graphics
  # imples: requires "opengl"  # for graphics
  # imples: requires "pixie"  # for complex paths (like text and svg) rendering


task docs, "Write the package docs":
  exec "nim doc --project --index:on --git.url:git@github.com:levovix0/sigui.git --git.commit:master -o:docs/apidocs src/sigui.nim"


