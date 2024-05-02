# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefix parseBlockComment:
  # Parse comments
  var commentNode = ast.newComment(p.curr)
  walk p
  if p.curr in {tkFnDef, tkFuncDef, tkFunctionDef}:
    return p.parseFunction(parent = commentNode)
  result = commentNode