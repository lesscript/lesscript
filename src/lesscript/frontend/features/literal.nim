# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefix parseBoolLit:
  # parse bool
  result = ast.newBool(p.curr)
  walk p

proc parseRange(p: var Parser, this: TokenTuple): Node =
  walk p # tkRangeLit
  expectWalk tkLB
  if p.curr is tkInteger:
    let lhs = p.curr
    walk p
    expectWalk tkDot
    expectWalk tkDot
    if p.curr is tkInteger:
      result = ast.newRange(this, lhs, p.curr)
      walk p
  expectWalkOrNil tkRB

newPrefix parseRangeLit:
  # parse a range type
  let this = p.curr
  return p.parseRange(this)

newPrefix parseFloatLit:
  # parse float
  result = ast.newFloat(p.curr)
  walk p

newPrefix parseIntLit:
  # parse int
  # if p.next == tkDot and p.next.line == p.curr.line:
  #   # kinda dirty
  #   let lhs = p.curr
  #   walk p
    # if p.next == tkDot:
      # return p.parseRangeValue(lhs)
  result = ast.newInt(p.curr)
  walk p

newPrefix parseStrLit:
  # parse a string
  result = ast.newStr(p.curr)
  walk p

newPrefix parseThis:
  result = ast.newCall(p.curr)
  walk p