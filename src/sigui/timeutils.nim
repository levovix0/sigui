import std/[times, strutils, math]


proc toSecs*(v: float): Duration =
  initDuration(seconds = v.int64, nanoseconds = ((v - v.int64.float) * 1_000_000_000).int64)

proc toMs*(v: float): Duration =
  initDuration(seconds = v.int64, nanoseconds = ((v - v.int64.float) * 1_000_000).int64)


proc `'s`*(lit: cstring): Duration =
  ($lit).parseFloat.toSecs

proc `'ms`*(lit: cstring): Duration =
  ($lit).parseFloat.toMs


proc secs*(d: Duration): float =
  d.inMicroseconds.float / 1e6

proc ms*(d: Duration): float =
  d.inMicroseconds.float / 1e3


proc `mod`*(a, b: Duration): Duration =
  (a.secs mod b.secs).toSecs

