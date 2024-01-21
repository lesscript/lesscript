# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefixProc "parseBoolLit":
  # parse bool
  result = ast.newBool(p.curr)
  walk p

newPrefixProc "parseFloatLit":
  # parse float
  result = ast.newFloat(p.curr)
  walk p

newPrefixProc "parseIntLit":
  # parse int
  result = ast.newInt(p.curr)
  walk p

newPrefixProc "parseStrLit":
  # parse a string
  result = ast.newStr(p.curr)
  walk p

newPrefixProc "parseThis":
  result = ast.newCall(p.curr)
  walk p