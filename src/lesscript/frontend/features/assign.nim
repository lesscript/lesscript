# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefix parseAssign:
  # parse a new assignment
  # todo newInfixProc
  let tk = p.curr
  let ident = ast.newId(p.curr)
  walk p, 2
  var node = p.parseAssignableNode()
  if likely(node != nil):
    result = ast.newAssignment(ident, node, tk)